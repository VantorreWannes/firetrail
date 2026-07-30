const std = @import("std");
const hashers = @import("../hashers.zig");
const luts = @import("../luts.zig");

pub const Encoder = WhiteEncoder(u64, u64, u8, u16, u16);
pub const Decoder = WhiteDecoder(u64, u64, u8, u16, u16);

pub fn WhiteEncoder(comptime Size: type, comptime Word: type, comptime Header: type, comptime Hash: type, comptime Cache: type) type {
    const Hasher = hashers.NumberHasher(Word, Hash, 0);
    const Table = luts.ArrayLookupTable(Hash, Word, std.math.maxInt(Cache) + 1);

    return struct {
        const Self = @This();

        const header_bits = @bitSizeOf(Header);
        const word_bytes = @sizeOf(Word);
        const header_bytes = @sizeOf(Header);
        const hash_bytes = @sizeOf(Hash);
        const size_bytes = @sizeOf(Size);
        const batch_bytes = header_bits * word_bytes;

        table: Table,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self = Self{ .table = try Table.init(allocator) };
            self.reset();
            return self;
        }

        pub fn fromReader(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Self {
            const table = try Table.fromReader(allocator, reader);
            return Self{ .table = table };
        }

        pub fn toWriter(self: *const Self, writer: *std.Io.Writer) !void {
            try self.table.toWriter(writer);
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.table.deinit(allocator);
            self.* = undefined;
        }

        pub fn outputBufferBound(len: usize) usize {
            const blocks = len / batch_bytes;
            return len + (blocks * header_bytes) + header_bytes + word_bytes + size_bytes;
        }

        pub fn compressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);

            var input_index: usize = 0;
            var output_index: usize = 0;
            const loop_limit = (input.len / batch_bytes) * batch_bytes;

            std.mem.writeInt(Size, output[0..size_bytes], @intCast(input.len), .little);
            output_index += size_bytes;

            while (input_index < loop_limit) {
                const header_pos = output_index;
                output_index += header_bytes;
                var header: Header = 0;

                inline for (0..header_bits) |token_index| {
                    const word = std.mem.readInt(Word, input[input_index..][0..word_bytes], .little);
                    input_index += word_bytes;

                    const hash = Hasher.hash(word);
                    if (word == self.table.get(hash)) {
                        std.mem.writeInt(Hash, output[output_index..][0..hash_bytes], hash, .little);
                        output_index += hash_bytes;
                        header |= 1 << token_index;
                    } else {
                        std.mem.writeInt(Word, output[output_index..][0..word_bytes], word, .little);
                        output_index += word_bytes;
                        self.table.set(hash, word);
                    }
                }

                std.mem.writeInt(Header, output[header_pos..][0..header_bytes], header, .little);
            }

            const remaining = input.len - input_index;
            if (remaining != 0) {
                @memcpy(output[output_index .. output_index + remaining], input[input_index .. input_index + remaining]);
                output_index += remaining;
            }

            return output_index;
        }

        pub fn reset(self: *Self) void {
            self.table.fill(0);
        }
    };
}

pub fn WhiteDecoder(comptime Size: type, comptime Word: type, comptime Header: type, comptime Hash: type, comptime Cache: type) type {
    return struct {
        const Self = @This();
        pub const Hasher = hashers.NumberHasher(Word, Hash, 0);
        pub const Table = luts.ArrayLookupTable(Hash, Word, std.math.maxInt(Cache) + 1);

        const header_bits = @bitSizeOf(Header);
        const word_bytes = @sizeOf(Word);
        const header_bytes = @sizeOf(Header);
        const hash_bytes = @sizeOf(Hash);
        const size_bytes = @sizeOf(Size);
        const batch_bytes = header_bits * word_bytes;

        table: Table,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self = Self{ .table = try Table.init(allocator) };
            self.reset();
            return self;
        }

        pub fn fromReader(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Self {
            const table = try Table.fromReader(allocator, reader);
            return Self{ .table = table };
        }

        pub fn toWriter(self: *const Self, writer: *std.Io.Writer) !void {
            try self.table.toWriter(writer);
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.table.deinit(allocator);
            self.* = undefined;
        }

        pub fn exactOutputLength(input: []const u8) usize {
            return @intCast(std.mem.readInt(Size, input[0..size_bytes], .little));
        }

        pub fn decompressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);

            const len = exactOutputLength(input);
            const loop_limit = (len / batch_bytes) * batch_bytes;

            var input_index: usize = size_bytes;
            var output_index: usize = 0;

            while (output_index < loop_limit) {
                const header = std.mem.readInt(Header, input[input_index..][0..header_bytes], .little);
                input_index += header_bytes;

                inline for (0..header_bits) |token_index| {
                    const word: Word = if ((header & (1 << token_index)) != 0) blk: {
                        const hash = std.mem.readInt(Hash, input[input_index..][0..hash_bytes], .little);
                        input_index += hash_bytes;
                        break :blk self.table.get(hash);
                    } else blk: {
                        const word = std.mem.readInt(Word, input[input_index..][0..word_bytes], .little);
                        input_index += word_bytes;
                        self.table.set(Hasher.hash(word), word);
                        break :blk word;
                    };

                    std.mem.writeInt(Word, output[output_index..][0..word_bytes], word, .little);
                    output_index += word_bytes;
                }
            }

            const remaining = len - output_index;
            if (remaining != 0) {
                @memcpy(output[output_index .. output_index + remaining], input[input_index .. input_index + remaining]);
                input_index += remaining;
            }

            return input_index;
        }

        pub fn reset(self: *Self) void {
            self.table.fill(0);
        }
    };
}
