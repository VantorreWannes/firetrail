const std = @import("std");
const hashers = @import("../hashers.zig");
const luts = @import("../luts.zig");

/// The default white encoder instantiation (64-bit words, 8-bit headers, 16-bit hashes and cache).
pub const Encoder = WhiteEncoder(u64, u64, u8, u16, u16);
/// The default white decoder instantiation (64-bit words, 8-bit headers, 16-bit hashes and cache).
pub const Decoder = WhiteDecoder(u64, u64, u8, u16, u16);

/// A dictionary encoder that replaces repeated words with their hashes.
///
/// The white variant uses a static dictionary: the table is never updated during
/// compression, so it must be trained beforehand (via `toSlice`/`fromSlice`).
///
/// Input is processed in batches of `@bitSizeOf(Header)` words; each batch is
/// preceded by a header whose bits mark which words were replaced by hashes.
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

        /// Creates an encoder with an empty (zeroed) dictionary.
        pub fn init(allocator: std.mem.Allocator) !Self {
            var self = Self{ .table = try Table.init(allocator) };
            self.reset();
            return self;
        }

        /// Creates an encoder with a dictionary previously written with `toSlice`.
        pub fn fromSlice(allocator: std.mem.Allocator, slice: []u8) !Self {
            const table = try Table.fromSlice(allocator, slice);
            return Self{ .table = table };
        }

        /// Writes the dictionary to `writer`, suitable for `fromSlice`.
        pub fn toSlice(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
            return try self.table.toSlice(allocator);
        }

        /// Frees the dictionary storage.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.table.deinit(allocator);
            self.* = undefined;
        }

        /// Returns the maximum number of bytes `compressBlockToBuffer` can write for `len` input bytes.
        pub fn outputBufferBound(len: usize) usize {
            const blocks = len / batch_bytes;
            return len + (blocks * header_bytes) + header_bytes + word_bytes + size_bytes;
        }

        /// Compresses `input` into `output`, which must be at least `outputBufferBound(input.len)`
        /// bytes long. Returns the number of bytes written.
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

        /// Clears the dictionary back to its initial zeroed state.
        pub fn reset(self: *Self) void {
            self.table.fill(0);
        }
    };
}

const testing = std.testing;

fn expectRoundTrip(comptime Enc: type, comptime Dec: type, input: []const u8) !void {
    var encoder = try Enc.init(testing.allocator);
    defer encoder.deinit(testing.allocator);
    var decoder = try Dec.init(testing.allocator);
    defer decoder.deinit(testing.allocator);

    const compressed = try testing.allocator.alloc(u8, Enc.outputBufferBound(input.len));
    defer testing.allocator.free(compressed);
    const compressed_len = encoder.compressBlockToBuffer(input, compressed);

    try testing.expectEqual(input.len, Dec.exactOutputLength(compressed[0..compressed_len]));

    const decompressed = try testing.allocator.alloc(u8, input.len);
    defer testing.allocator.free(decompressed);
    const consumed = decoder.decompressBlockToBuffer(compressed[0..compressed_len], decompressed);

    try testing.expectEqual(compressed_len, consumed);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "round trip" {
    const input = "the quick brown fox jumps over the lazy dog, the quick brown fox";
    try expectRoundTrip(Encoder, Decoder, input);
}

test "round trip with trailing partial batch" {
    const input = "abc";
    try expectRoundTrip(Encoder, Decoder, input);
}

/// A dictionary decoder that reconstructs words from their hashes.
///
/// The white variant mirrors `WhiteEncoder`: it uses a static dictionary that must
/// match the one used during compression.
pub fn WhiteDecoder(comptime Size: type, comptime Word: type, comptime Header: type, comptime Hash: type, comptime Cache: type) type {
    return struct {
        const Self = @This();
        /// The hasher used to derive dictionary keys from words.
        pub const Hasher = hashers.NumberHasher(Word, Hash, 0);
        /// The dictionary table type.
        pub const Table = luts.ArrayLookupTable(Hash, Word, std.math.maxInt(Cache) + 1);

        const header_bits = @bitSizeOf(Header);
        const word_bytes = @sizeOf(Word);
        const header_bytes = @sizeOf(Header);
        const hash_bytes = @sizeOf(Hash);
        const size_bytes = @sizeOf(Size);
        const batch_bytes = header_bits * word_bytes;

        table: Table,

        /// Creates a decoder with an empty (zeroed) dictionary.
        pub fn init(allocator: std.mem.Allocator) !Self {
            var self = Self{ .table = try Table.init(allocator) };
            self.reset();
            return self;
        }

        /// Creates an encoder with a dictionary previously written with `toSlice`.
        pub fn fromSlice(allocator: std.mem.Allocator, slice: []u8) !Self {
            const table = try Table.fromSlice(allocator, slice);
            return Self{ .table = table };
        }

        /// Writes the dictionary to `writer`, suitable for `fromSlice`.
        pub fn toSlice(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
            return try self.table.toSlice(allocator);
        }

        /// Frees the dictionary storage.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.table.deinit(allocator);
            self.* = undefined;
        }

        /// Returns the maximum number of compressed bytes a block of `len` decompressed bytes can occupy.
        pub fn outputBufferBound(len: usize) usize {
            const blocks = len / batch_bytes;
            return len + (blocks * header_bytes) + header_bytes + word_bytes + size_bytes;
        }

        /// Returns the decompressed length of a block produced by `compressBlockToBuffer`.
        pub fn exactOutputLength(input: []const u8) usize {
            return @intCast(std.mem.readInt(Size, input[0..size_bytes], .little));
        }

        /// Decompresses a block produced by `compressBlockToBuffer` into `output`, which must
        /// be at least `exactOutputLength(input)` bytes long. Returns the number of input bytes consumed.
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
