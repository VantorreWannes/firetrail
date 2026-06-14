const std = @import("std");
const hashers = @import("../hashers.zig");
const luts = @import("../luts.zig");

pub const Encoder = OrangeEncoder(u64, u8, u16);
pub const Decoder = OrangeDecoder(u64, u8, u16);

pub fn OrangeEncoder(comptime Word: type, comptime Header: type, comptime Hash: type) type {
    const Hasher = hashers.NumberHasher(Word, Hash);
    const Table = luts.LookupTable(Hash, Word);
    const Size = u64;
    const Mask = Word;

    const HEADER_BITS = @bitSizeOf(Header);
    const WORD_BYTES = @sizeOf(Word);
    const HEADER_BYTES = @sizeOf(Header);
    const HASH_BYTES = @sizeOf(Hash);
    const SIZE_BYTES = @sizeOf(Size);
    const BATCH_BYTES: usize = HEADER_BITS * WORD_BYTES;

    const MIN_BYTES_LEFT: usize = HASH_BYTES + 1;
    const MAX_MASKED_BYTES: usize = WORD_BYTES -| MIN_BYTES_LEFT;
    const MAX_WORD_VARIATIONS: usize = MAX_MASKED_BYTES + 1;

    return struct {
        const Self = @This();
        tables: [MAX_WORD_VARIATIONS]Table,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var tables: [MAX_WORD_VARIATIONS]Table = undefined;
            var initialized: usize = 0;
            errdefer {
                for (0..initialized) |index| {
                    tables[index].deinit(allocator);
                }
            }
            for (0..MAX_WORD_VARIATIONS) |index| {
                tables[index] = try Table.init(allocator);
                initialized += 1;
                tables[index].fill(0);
            }
            return Self{ .tables = tables };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            inline for (0..MAX_WORD_VARIATIONS) |index| self.tables[index].deinit(allocator);
        }

        pub inline fn outputBufferBound(len: usize) usize {
            const blocks = len / BATCH_BYTES;
            return len + (blocks * HEADER_BYTES) + HEADER_BYTES + WORD_BYTES + SIZE_BYTES;
        }

        inline fn maskedWords(word: Word) [MAX_WORD_VARIATIONS]Mask {
            var masked_words: [MAX_WORD_VARIATIONS]Mask = undefined;
            inline for (0..MAX_WORD_VARIATIONS) |mask_byte_size| {
                const mask = ~@as(Word, 0) << @intCast(mask_byte_size * 8);
                masked_words[mask_byte_size] = word & mask;
            }
            return masked_words;
        }

        pub fn compressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);

            var input_index: usize = 0;
            var output_index: usize = 0;
            const loop_limit = (input.len / BATCH_BYTES) * BATCH_BYTES;

            std.mem.writeInt(Size, output[0..SIZE_BYTES], @intCast(input.len), .little);
            output_index += SIZE_BYTES;

            while (input_index < loop_limit) {
                const header_pos = output_index;
                output_index += HEADER_BYTES;
                var header: Header = 0;

                @setEvalBranchQuota(10000);

                inline for (0..HEADER_BITS) |token_index| {
                    const word = std.mem.readInt(Word, input[input_index..][0..WORD_BYTES], .little);
                    defer input_index += WORD_BYTES;

                    const masked_words = Self.maskedWords(word);

                    inline for (0..MAX_WORD_VARIATIONS) |masked_word_index| {
                        const masked_word = masked_words[masked_word_index];
                        const hash = Hasher.hash(masked_word);
                        if (self.tables[masked_word_index].get(hash) == masked_word) {
                            std.mem.writeInt(Hash, output[output_index..][0..HASH_BYTES], hash, .little);
                            output_index += HASH_BYTES;
                            std.mem.writeInt(Word, output[output_index..][0..WORD_BYTES], word, .little);
                            output_index += masked_word_index;

                            header |= @as(Header, 1) << @intCast(token_index);

                            inline for (0..masked_word_index) |strong_idx| {
                                const strong_masked = masked_words[strong_idx];
                                const strong_hash = Hasher.hash(strong_masked);
                                self.tables[strong_idx].set(strong_hash, strong_masked);
                            }

                            break;
                        }
                    } else {
                        std.mem.writeInt(Word, output[output_index..][0..WORD_BYTES], word, .little);
                        output_index += WORD_BYTES;

                        inline for (0..MAX_WORD_VARIATIONS) |masked_word_index| {
                            const masked_word = masked_words[masked_word_index];
                            const hash = Hasher.hash(masked_word);
                            self.tables[masked_word_index].set(hash, masked_word);
                        }
                    }
                }

                std.mem.writeInt(Header, output[header_pos..][0..HEADER_BYTES], header, .little);
            }

            const remaining = input.len - input_index;
            if (remaining != 0) {
                @memcpy(output[output_index .. output_index + remaining], input[input_index .. input_index + remaining]);
                output_index += remaining;
            }

            return output_index;
        }
    };
}

pub fn OrangeDecoder(comptime Word: type, comptime Header: type, comptime Hash: type) type {
    const Hasher = hashers.NumberHasher(Word, Hash);
    const Table = luts.LookupTable(Hash, Word);
    const Size = u64;

    const HEADER_BITS = @bitSizeOf(Header);
    const WORD_BYTES = @sizeOf(Word);
    const HEADER_BYTES = @sizeOf(Header);
    const HASH_BYTES = @sizeOf(Hash);
    const SIZE_BYTES = @sizeOf(Size);
    const BATCH_BYTES = HEADER_BITS * WORD_BYTES;
    const MIN_BYTES_LEFT: usize = HASH_BYTES + 1;
    const MAX_MASKED_BYTES: usize = WORD_BYTES -| MIN_BYTES_LEFT;

    return struct {
        const Self = @This();
        table: Table,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var table = try Table.init(allocator);
            table.fill(0);
            return .{ .table = table };
        }

        pub inline fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.table.deinit(allocator);
        }

        pub inline fn exactOutputLength(input: []const u8) usize {
            return @intCast(std.mem.readInt(Size, input[0..SIZE_BYTES], .little));
        }

        inline fn setWordEntries(self: *Self, word: Word) void {
            inline for (0..MAX_MASKED_BYTES) |masked_bytes| {
                const mask = ~@as(Word, 0) << @intCast(masked_bytes * 8);
                const masked_word = word & mask;
                const hash = Hasher.hash(masked_word);
                self.table.set(hash, word);
            }
        }

        pub fn decompressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);

            const len = exactOutputLength(input);
            const loop_limit = (len / BATCH_BYTES) * BATCH_BYTES;

            var input_index: usize = SIZE_BYTES;
            var output_index: usize = 0;

            while (output_index < loop_limit) {
                const header = std.mem.readInt(Header, input[input_index..][0..HEADER_BYTES], .little);
                input_index += HEADER_BYTES;

                inline for (0..HEADER_BITS) |token_index| {
                    var word: Word = undefined;

                    if ((header & (@as(Header, 1) << @intCast(token_index))) != 0) {
                        const hash = std.mem.readInt(Hash, input[input_index..][0..HASH_BYTES], .little);
                        input_index += HASH_BYTES;
                        word = self.table.get(hash);
                    } else {
                        word = std.mem.readInt(Word, input[input_index..][0..WORD_BYTES], .little);
                        input_index += WORD_BYTES;

                        self.setWordEntries(word);
                    }

                    std.mem.writeInt(Word, output[output_index..][0..WORD_BYTES], word, .little);
                    output_index += WORD_BYTES;
                }
            }

            const remaining = len - output_index;
            if (remaining != 0) {
                @memcpy(output[output_index .. output_index + remaining], input[input_index .. input_index + remaining]);
                input_index += remaining;
            }

            return input_index;
        }
    };
}
