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

        test hash {
            {
                const expected = 0;
                try std.testing.expectEqual(expected, Self.hash(expected));
            }
            {
                const expected = 1;
                try std.testing.expect(expected != Self.hash(expected));
            }
        }
    };
}

test {
    {
        std.testing.refAllDecls(NumberHasher(u8, u8));
    }
    {
        std.testing.refAllDecls(NumberHasher(u16, u8));
        std.testing.refAllDecls(NumberHasher(u16, u16));
    }
    {
        std.testing.refAllDecls(NumberHasher(u32, u8));
        std.testing.refAllDecls(NumberHasher(u32, u16));
        std.testing.refAllDecls(NumberHasher(u32, u32));
    }
    {
        std.testing.refAllDecls(NumberHasher(u64, u8));
        std.testing.refAllDecls(NumberHasher(u64, u16));
        std.testing.refAllDecls(NumberHasher(u64, u32));
        std.testing.refAllDecls(NumberHasher(u64, u64));
    }
    {
        std.testing.refAllDecls(NumberHasher(u128, u8));
        std.testing.refAllDecls(NumberHasher(u128, u16));
        std.testing.refAllDecls(NumberHasher(u128, u32));
        std.testing.refAllDecls(NumberHasher(u128, u64));
        std.testing.refAllDecls(NumberHasher(u128, u128));
    }
}
