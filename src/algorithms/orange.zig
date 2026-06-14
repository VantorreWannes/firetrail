const std = @import("std");
const hashers = @import("../hashers.zig");
const luts = @import("../luts.zig");

pub const Encoder = OrangeEncoder(u64, u8, u16);
pub const Decoder = OrangeDecoder(u64, u8, u16);

pub fn OrangeEncoder(comptime Word: type, comptime Header: type, comptime Hash: type) type {
    const Size = u64;
    const Mask = Word;

    const HEADER_BITS = @bitSizeOf(Header);
    const HEADER_BYTES = @sizeOf(Header);

    const WORD_BYTES = @sizeOf(Word);

    const HASH_BYTES = @sizeOf(Hash);

    const SIZE_BYTES = @sizeOf(Size);

    const MASK_BYTES = @sizeOf(Mask);

    const BATCH_BYTES: usize = HEADER_BITS * WORD_BYTES;

    const MIN_GAINED_BYTES: usize = 1;

    const MAX_MASKED_BYTES: usize = MASK_BYTES -| (HASH_BYTES + MIN_GAINED_BYTES);

    const MAX_WORD_VARIATIONS: usize = MAX_MASKED_BYTES + 1;

    const Hasher = hashers.NumberHasher(Word, Hash);
    const Table = luts.LookupTable(Hash, Word);

    return struct {
        const Self = @This();
        tables: [MAX_WORD_VARIATIONS]Table,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var tables = [_]Table{.{ .table = Table.empty }} ** MAX_WORD_VARIATIONS;

            errdefer for (&tables) |*table| table.deinit(allocator);

            for (&tables) |*table| {
                table.* = try Table.init(allocator);
                table.fill(0);
            }

            return Self{ .tables = tables };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (&self.tables) |*table| table.deinit(allocator);
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

        inline fn updateTables(self: *Self, comptime limit: usize, masked_words: [MAX_WORD_VARIATIONS]Mask) void {
            inline for (0..limit) |strong_idx| {
                const strong_masked = masked_words[strong_idx];
                const strong_hash = Hasher.hash(strong_masked);
                self.tables[strong_idx].set(strong_hash, strong_masked);
            }
        }

        pub fn compressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);
            @setEvalBranchQuota(10000);

            var input_index: usize = 0;
            var output_index: usize = 0;
            const loop_limit = (input.len / BATCH_BYTES) * BATCH_BYTES;

            std.mem.writeInt(Size, output[0..SIZE_BYTES], @intCast(input.len), .little);
            output_index += SIZE_BYTES;

            while (input_index < loop_limit) {
                const header_pos = output_index;
                output_index += HEADER_BYTES;
                var header: Header = 0;

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

                            header |= 1 << token_index;

                            self.updateTables(masked_word_index, masked_words);

                            break;
                        }
                    } else {
                        std.mem.writeInt(Word, output[output_index..][0..WORD_BYTES], word, .little);
                        output_index += WORD_BYTES;

                        self.updateTables(MAX_WORD_VARIATIONS, masked_words);
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
    const Size = u64;
    const Mask = Word;

    const HEADER_BITS = @bitSizeOf(Header);
    const HEADER_BYTES = @sizeOf(Header);

    const WORD_BYTES = @sizeOf(Word);

    const HASH_BYTES = @sizeOf(Hash);

    const SIZE_BYTES = @sizeOf(Size);

    const MASK_BYTES = @sizeOf(Mask);

    const BATCH_BYTES: usize = HEADER_BITS * WORD_BYTES;

    const MIN_GAINED_BYTES: usize = 1;

    const MAX_MASKED_BYTES: usize = MASK_BYTES -| (HASH_BYTES + MIN_GAINED_BYTES);

    const MAX_WORD_VARIATIONS: usize = MAX_MASKED_BYTES + 1;

    const Hasher = hashers.NumberHasher(Word, Hash);
    const Table = luts.LookupTable(Hash, Word);

    return struct {
        const Self = @This();
        tables: [MAX_WORD_VARIATIONS]Table,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var tables = [_]Table{.{ .table = Table.empty }} ** MAX_WORD_VARIATIONS;

            errdefer for (&tables) |*table| table.deinit(allocator);

            for (&tables) |*table| {
                table.* = try Table.init(allocator);
                table.fill(0);
            }

            return Self{ .tables = tables };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (&self.tables) |*table| table.deinit(allocator);
        }

        pub inline fn exactOutputLength(input: []const u8) usize {
            return @intCast(std.mem.readInt(Size, input[0..SIZE_BYTES], .little));
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

        inline fn updateTables(self: *Self, comptime limit: usize, masked_words: [MAX_WORD_VARIATIONS]Mask) void {
            inline for (0..limit) |strong_idx| {
                const strong_masked = masked_words[strong_idx];
                const strong_hash = Hasher.hash(strong_masked);
                self.tables[strong_idx].set(strong_hash, strong_masked);
            }
        }

        inline fn decodeMatch(self: *Self, hash: Hash, input: []const u8, input_index: *usize) Word {
            inline for (0..MAX_WORD_VARIATIONS) |masked_word_index| {
                const masked_word = self.tables[masked_word_index].get(hash);
                if (Hasher.hash(masked_word) == hash) {
                    var literal: Word = 0;
                    @memcpy(std.mem.asBytes(&literal)[0..masked_word_index], input[input_index.*..][0..masked_word_index]);
                    input_index.* += masked_word_index;

                    const word = masked_word | literal;
                    self.updateTables(masked_word_index, Self.maskedWords(word));
                    return word;
                }
            }
            unreachable;
        }

        pub fn decompressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);
            @setEvalBranchQuota(10000);

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

                        word = self.decodeMatch(hash, input, &input_index);
                    } else {
                        word = std.mem.readInt(Word, input[input_index..][0..WORD_BYTES], .little);
                        input_index += WORD_BYTES;

                        const masked_words = Self.maskedWords(word);
                        self.updateTables(MAX_WORD_VARIATIONS, masked_words);
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
