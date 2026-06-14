const std = @import("std");

pub fn LookupTable(comptime Key: type, comptime Value: type) type {
    return struct {
        const Self = @This();
        const SIZE = 1 << @bitSizeOf(Key);

        table: []Value,

        pub const empty = &[_]Value{};

        pub inline fn init(allocator: std.mem.Allocator) !Self {
            const table = try allocator.alloc(Value, SIZE);
            return Self{ .table = table };
        }

        pub inline fn fill(self: *Self, value: Value) void {
            @memset(self.table, value);
        }

        pub inline fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.table);
        }

        pub inline fn get(self: *const Self, key: Key) Value {
            return self.table[key];
        }

        pub inline fn set(self: *Self, key: Key, value: Value) void {
            self.table[key] = value;
        }
    };
}

test "init + deinit" {
    const allocator = std.testing.allocator;
    const Lut = LookupTable(u16, u32);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);
}

test "set" {
    const allocator = std.testing.allocator;
    const Lut = LookupTable(u8, u8);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);

    lut.set(0, 0);
    try std.testing.expectEqual(0, lut.get(0));
}

test "get" {
    const allocator = std.testing.allocator;
    const Lut = LookupTable(u8, u8);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);

    lut.set(0, 0);
    try std.testing.expectEqual(0, lut.get(0));
}

test "fill" {
    const allocator = std.testing.allocator;
    const Lut = LookupTable(u8, u8);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);

    lut.fill(0);
    try std.testing.expectEqual(0, lut.get(1));
}
