const std = @import("std");
const hashers = @import("../hashers.zig");
const luts = @import("../luts.zig");

pub const Encoder = WhiteEncoder(u64, u8, u16);
pub const Decoder = WhiteDecoder(u64, u8, u16);

pub fn WhiteEncoder(comptime Word: type, comptime Header: type, comptime Hash: type) type {
    const Hasher = hashers.NumberHasher(Word, Hash);
    const Table = luts.LookupTable(Hash, Word);
    const Size = u64;

    const HEADER_BITS = @bitSizeOf(Header);
    const WORD_BYTES = @sizeOf(Word);
    const HEADER_BYTES = @sizeOf(Header);
    const HASH_BYTES = @sizeOf(Hash);
    const SIZE_BYTES = @sizeOf(Size);
    const BATCH_BYTES = HEADER_BITS * WORD_BYTES;

    return struct {
        const Self = @This();
        table: Table,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var table = try Table.init(allocator);
            table.fill(0);
            return .{ .table = table };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.table.deinit(allocator);
        }

        pub inline fn outputBufferBound(len: usize) usize {
            const blocks = len / BATCH_BYTES;
            return len + (blocks * HEADER_BYTES) + HEADER_BYTES + WORD_BYTES + SIZE_BYTES;
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

                inline for (0..HEADER_BITS) |token_index| {
                    const word = std.mem.readInt(Word, input[input_index..][0..WORD_BYTES], .little);
                    input_index += WORD_BYTES;

                    const hash = Hasher.hash(word);
                    if (word == self.table.get(hash)) {
                        std.mem.writeInt(Hash, output[output_index..][0..HASH_BYTES], hash, .little);
                        output_index += HASH_BYTES;
                        header |= 1 << token_index;
                    } else {
                        std.mem.writeInt(Word, output[output_index..][0..WORD_BYTES], word, .little);
                        output_index += WORD_BYTES;
                        self.table.set(hash, word);
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

pub fn WhiteDecoder(comptime Word: type, comptime Header: type, comptime Hash: type) type {
    const Hasher = hashers.NumberHasher(Word, Hash);
    const Table = luts.LookupTable(Hash, Word);
    const Size = u64;

    const HEADER_BITS = @bitSizeOf(Header);
    const WORD_BYTES = @sizeOf(Word);
    const HEADER_BYTES = @sizeOf(Header);
    const HASH_BYTES = @sizeOf(Hash);
    const SIZE_BYTES = @sizeOf(Size);
    const BATCH_BYTES = HEADER_BITS * WORD_BYTES;

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

                    if ((header & (1 << token_index)) != 0) {
                        const hash = std.mem.readInt(Hash, input[input_index..][0..HASH_BYTES], .little);
                        input_index += HASH_BYTES;
                        word = self.table.get(hash);
                    } else {
                        word = std.mem.readInt(Word, input[input_index..][0..WORD_BYTES], .little);
                        input_index += WORD_BYTES;
                        self.table.set(Hasher.hash(word), word);
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
