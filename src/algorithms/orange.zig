const std = @import("std");

const hashers = @import("../hashers.zig");
const luts = @import("../luts.zig");

pub const Encoder = OrangeEncoder(u32, u16);
pub const Decoder = OrangeDecoder(u32, u16);

fn TablesTypes(comptime Word: type, comptime Hash: type) [@sizeOf(Word) - @sizeOf(Hash)]type {
    const WORD_BYTES = @sizeOf(Word);
    const HASH_BYTES = @sizeOf(Hash);
    const TABLES_COUNT = WORD_BYTES - HASH_BYTES;

    var types: [TABLES_COUNT]type = undefined;
    inline for (&types, 0..) |*t, i| {
        const size = WORD_BYTES - i;
        t.* = luts.ArrayLookupTable(Hash, std.meta.Int(.unsigned, size * 8));
    }
    return types;
}

pub fn OrangeEncoder(comptime Word: type, comptime Hash: type) type {
    const Size = u64;

    const WORD_BYTES = @sizeOf(Word);
    const HASH_BYTES = @sizeOf(Hash);
    const SIZE_BYTES = @sizeOf(Size);

    const table_types = comptime TablesTypes(Word, Hash);
    const Tables = luts.StructLookupTable(&table_types);
    const Hasher = hashers.NumberHasher(Word, Hash);

    const TABLES_COUNT = table_types.len;
    const LITERAL_STATE = TABLES_COUNT;
    const BATCH_SIZE = 8;

    const LayerBits = std.math.log2_int_ceil(usize, TABLES_COUNT + 1);

    const HEADER_BITS = BATCH_SIZE * LayerBits;
    const Header = std.meta.Int(.unsigned, HEADER_BITS);
    const HEADER_BYTES = HEADER_BITS / 8;

    const BATCH_BYTES: usize = BATCH_SIZE * WORD_BYTES;

    return struct {
        const Self = @This();
        tables: Tables,

        pub fn init(allocator: std.mem.Allocator) !Self {
            @setEvalBranchQuota(10000);
            var tables = Tables.empty;
            errdefer inline for (0..Tables.SIZE) |index| tables.get(index).deinit(allocator);
            inline for (table_types, 0..) |Table, index| tables.set(index, try Table.init(allocator));
            return Self{ .tables = tables };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            inline for (0..Tables.SIZE) |index| self.tables.get(index).deinit(allocator);
        }

        pub inline fn outputBufferBound(len: usize) usize {
            const blocks = len / BATCH_BYTES;
            return len + (blocks * HEADER_BYTES) + HEADER_BYTES + WORD_BYTES + SIZE_BYTES;
        }

        pub fn compressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);
            @setEvalBranchQuota(100000);

            var input_index: usize = 0;
            var output_index: usize = 0;
            const loop_limit = (input.len / BATCH_BYTES) * BATCH_BYTES;

            std.mem.writeInt(Size, output[0..SIZE_BYTES], @intCast(input.len), .little);
            output_index += SIZE_BYTES;

            while (input_index < loop_limit) {
                const header_pos = output_index;
                output_index += HEADER_BYTES;
                var header: Header = 0;

                inline for (0..BATCH_SIZE) |token_index| {
                    const word = std.mem.readInt(Word, input[input_index..][0..WORD_BYTES], .little);
                    input_index += WORD_BYTES;

                    inline for (0..Tables.SIZE) |index| {
                        const table = self.tables.get(index);
                        const Table = @TypeOf(table.*);
                        const MaskedWord = Table.V;
                        const masked_word: MaskedWord = @truncate(word);
                        const hash = Hasher.hash(masked_word);
                        defer table.set(hash, masked_word);

                        if (masked_word == table.get(hash)) {
                            std.mem.writeInt(Hash, output[output_index..][0..HASH_BYTES], hash, .little);
                            output_index += HASH_BYTES;

                            const masked_word_bytes = @bitSizeOf(MaskedWord) / 8;
                            const remaining_bytes = WORD_BYTES - masked_word_bytes;
                            const word_bytes = std.mem.asBytes(&word);
                            @memcpy(output[output_index..][0..remaining_bytes], word_bytes[masked_word_bytes..WORD_BYTES]);
                            output_index += remaining_bytes;

                            header |= index << token_index * LayerBits;
                            break;
                        }
                    } else {
                        std.mem.writeInt(Word, output[output_index..][0..WORD_BYTES], word, .little);
                        output_index += WORD_BYTES;
                        header |= @as(Header, LITERAL_STATE) << @intCast(token_index * LayerBits);
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

        pub fn reset(self: *Self) void {
            inline for (0..Tables.SIZE) |index| self.tables.get(index).fill(0);
        }
    };
}

pub fn OrangeDecoder(comptime Word: type, comptime Hash: type) type {
    const Size = u64;

    const WORD_BYTES = @sizeOf(Word);
    const HASH_BYTES = @sizeOf(Hash);
    const SIZE_BYTES = @sizeOf(Size);

    const table_types = comptime TablesTypes(Word, Hash);
    const Tables = luts.StructLookupTable(&table_types);
    const Hasher = hashers.NumberHasher(Word, Hash);

    const TABLES_COUNT = table_types.len;
    const LITERAL_STATE = TABLES_COUNT;
    const BATCH_SIZE = 8;

    const LayerBits = std.math.log2_int_ceil(usize, TABLES_COUNT + 1);
    const Layer = std.meta.Int(.unsigned, LayerBits);

    const HEADER_BITS = BATCH_SIZE * LayerBits;
    const Header = std.meta.Int(.unsigned, HEADER_BITS);
    const HEADER_BYTES = HEADER_BITS / 8;

    const BATCH_BYTES: usize = BATCH_SIZE * WORD_BYTES;

    return struct {
        const Self = @This();
        tables: Tables,

        pub fn init(allocator: std.mem.Allocator) !Self {
            @setEvalBranchQuota(10000);
            var tables = Tables.empty;
            errdefer inline for (0..Tables.SIZE) |index| tables.get(index).deinit(allocator);
            inline for (table_types, 0..) |Table, index| tables.set(index, try Table.init(allocator));
            return Self{ .tables = tables };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            inline for (0..Tables.SIZE) |index| self.tables.get(index).deinit(allocator);
        }

        pub inline fn exactOutputLength(input: []const u8) usize {
            return @intCast(std.mem.readInt(Size, input[0..SIZE_BYTES], .little));
        }

        pub inline fn outputBufferBound(len: usize) usize {
            const blocks = len / BATCH_BYTES;
            return len + (blocks * HEADER_BYTES) + HEADER_BYTES + WORD_BYTES + SIZE_BYTES;
        }

        pub fn decompressBlockToBuffer(self: *Self, noalias input: []const u8, noalias output: []u8) usize {
            @setRuntimeSafety(false);
            @setEvalBranchQuota(100000);

            const len = exactOutputLength(input);
            const loop_limit = (len / BATCH_BYTES) * BATCH_BYTES;

            var input_index: usize = SIZE_BYTES;
            var output_index: usize = 0;

            while (output_index < loop_limit) {
                const header = std.mem.readInt(Header, input[input_index..][0..HEADER_BYTES], .little);
                input_index += HEADER_BYTES;

                inline for (0..BATCH_SIZE) |token_index| {
                    var word: Word = 0;
                    const layer_val: Layer = @truncate(header >> @intCast(token_index * LayerBits));

                    if (layer_val == LITERAL_STATE) {
                        word = std.mem.readInt(Word, input[input_index..][0..WORD_BYTES], .little);
                        input_index += WORD_BYTES;

                        inline for (0..Tables.SIZE) |index| {
                            const table = self.tables.get(index);
                            const Table = @TypeOf(table.*);
                            const MaskedWord = Table.V;
                            const masked_word: MaskedWord = @truncate(word);
                            table.set(Hasher.hash(masked_word), masked_word);
                        }
                    } else {
                        const hash = std.mem.readInt(Hash, input[input_index..][0..HASH_BYTES], .little);
                        input_index += HASH_BYTES;

                        switch (layer_val) {
                            inline 0...TABLES_COUNT - 1 => |index| {
                                const table = self.tables.get(index);
                                const Table = @TypeOf(table.*);
                                const MaskedWord = Table.V;
                                const masked_word = table.get(hash);

                                const masked_word_bytes = @bitSizeOf(MaskedWord) / 8;
                                const remaining_bytes = WORD_BYTES - masked_word_bytes;
                                const word_bytes = std.mem.asBytes(&word);
                                const masked_bytes = std.mem.asBytes(&masked_word);

                                @memcpy(word_bytes[0..masked_word_bytes], masked_bytes[0..masked_word_bytes]);
                                @memcpy(word_bytes[masked_word_bytes..WORD_BYTES], input[input_index..][0..remaining_bytes]);
                                input_index += remaining_bytes;

                                inline for (0..index + 1) |update_idx| {
                                    const u_table = self.tables.get(update_idx);
                                    const UMaskedWord = @TypeOf(u_table.*).V;
                                    const u_masked: UMaskedWord = @truncate(word);
                                    u_table.set(Hasher.hash(u_masked), u_masked);
                                }
                            },
                            else => unreachable,
                        }
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

        pub fn reset(self: *Self) void {
            inline for (0..Tables.SIZE) |index| self.tables.get(index).fill(0);
        }
    };
}
