const std = @import("std");

pub fn NumberHasher(comptime Data: type, comptime Hash: type) type {
    if (@bitSizeOf(Data) < @bitSizeOf(Hash)) @compileError("Data type cannot be larger than Hash type");
    return struct {
        const Self = @This();
        const PRIME = switch (Data) {
            u128 => 0x9E3779B97F4A7C15F39CC0605CEDC7FD,
            u64 => 0x9E3779B97F4A7C15,
            u32 => 0x9D6EF916,
            u16 => 0x9E3B,
            u8 => 0x9D,
            else => @compileError("Unsupported Data type size for Hasher"),
        };
        const SHIFT = @bitSizeOf(Data) - @bitSizeOf(Hash);

        pub inline fn hash(data: Data) Hash {
            return @truncate((data *% PRIME) >> SHIFT);
        }
    };
}

test "hash" {
    const Hasher = NumberHasher(u64, u16);
    try std.testing.expectEqual(40503, Hasher.hash(1));
}
