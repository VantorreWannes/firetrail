const std = @import("std");

pub fn ArrayLookupTable(comptime Key: type, comptime Value: type) type {
    return struct {
        const Self = @This();
        const size = 1 << @bitSizeOf(Key);

        pub const K = Key;
        pub const V = Value;

        table: []Value,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{ .table = try allocator.alloc(Value, size) };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.table);
            self.* = undefined;
        }

        pub fn fill(self: *Self, value: Value) void {
            @memset(self.table, value);
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
    const Lut = ArrayLookupTable(u16, u32);
    var lut = try Lut.init(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
}

test "set" {
    const Lut = ArrayLookupTable(u8, u8);
    var lut = try Lut.init(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
    lut.set(0, 0);
    try std.testing.expectEqual(@as(u8, 0), lut.get(0));
}

test "get" {
    const Lut = ArrayLookupTable(u8, u8);
    var lut = try Lut.init(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
    lut.set(0, 0);
    try std.testing.expectEqual(@as(u8, 0), lut.get(0));
}

test "fill" {
    const Lut = ArrayLookupTable(u8, u8);
    var lut = try Lut.init(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
    lut.fill(0);
    try std.testing.expectEqual(@as(u8, 0), lut.get(1));
}

pub fn StructLookupTable(comptime lookup_table_types: []const type) type {
    comptime var field_names: [lookup_table_types.len][]const u8 = undefined;
    inline for (&field_names, 0..) |*name, index| {
        name.* = std.mem.asBytes(index);
    }

    const Container = @Struct(
        .auto,
        null,
        &field_names,
        lookup_table_types[0..lookup_table_types.len],
        &@splat(.{}),
    );

    return struct {
        const Self = @This();

        pub const size = lookup_table_types.len;

        container: Container,

        pub fn get(self: *Self, comptime index: usize) *lookup_table_types[index] {
            const field_name = comptime std.mem.asBytes(index);
            return &@field(self.container, field_name);
        }

        pub fn set(self: *Self, comptime index: usize, value: lookup_table_types[index]) void {
            const field_name = comptime std.mem.asBytes(index);
            @field(self.container, field_name) = value;
        }
    };
}
