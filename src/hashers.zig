const std = @import("std");

pub fn NumberHasher(comptime Data: type, comptime Hash: type, comptime seed: Data) type {
    const data_info = @typeInfo(Data);
    const hash_info = @typeInfo(Hash);
    const data_size = @bitSizeOf(Data);
    const hash_size = @bitSizeOf(Hash);

    if (data_info != .int or data_info.int.signedness != .unsigned)
        @compileError("NumberHasher requires an unsigned integer Data type, got: " ++ @typeName(Data));
    if (hash_info != .int or hash_info.int.signedness != .unsigned)
        @compileError("NumberHasher requires an unsigned integer Hash type, got: " ++ @typeName(Hash));
    if (hash_size > data_size)
        @compileError("Hash bit size must not exceed Data bit size");

    return struct {
        const PRIME: Data = fibonacciPrime(@bitSizeOf(Data)) ^ (seed | 1);
        const SHIFT = @bitSizeOf(Data) - @bitSizeOf(Hash);

        pub inline fn hash(data: Data) Hash {
            return @truncate((data *% PRIME) >> SHIFT);
        }

        fn fibonacciPrime(comptime bits: comptime_int) comptime_int {
            const target: comptime_int = 5 << (2 * (bits - 1));
            var x: comptime_int = @as(comptime_int, 1) << (bits + 1);
            while (true) {
                const next = (x + target / x) >> 1;
                if (next >= x) break;
                x = next;
            }
            return (x - (@as(comptime_int, 1) << (bits - 1))) | 1;
        }
    };
}

test "hash" {
    const Hasher = NumberHasher(u64, u16, 0);
    try std.testing.expectEqual(40503, Hasher.hash(1));
}

test "seeds produce different hashes" {
    const H1 = NumberHasher(u64, u16, 0);
    const H2 = NumberHasher(u64, u16, 0x9E3779B97F4A7C15);
    var differ: usize = 0;
    for (0..1000) |i| {
        if (H1.hash(i) != H2.hash(i)) differ += 1;
    }
    try std.testing.expect(differ > 900);
}
