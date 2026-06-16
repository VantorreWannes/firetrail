const std = @import("std");

pub fn ArrayLookupTable(comptime Key: type, comptime Value: type) type {
    return struct {
        const Self = @This();
        const SIZE = 1 << @bitSizeOf(Key);
        pub const K = Key;
        pub const V = Value;

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
    const Lut = ArrayLookupTable(u16, u32);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);
}

test "set" {
    const allocator = std.testing.allocator;
    const Lut = ArrayLookupTable(u8, u8);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);

    lut.set(0, 0);
    try std.testing.expectEqual(0, lut.get(0));
}

test "get" {
    const allocator = std.testing.allocator;
    const Lut = ArrayLookupTable(u8, u8);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);

    lut.set(0, 0);
    try std.testing.expectEqual(0, lut.get(0));
}

test "fill" {
    const allocator = std.testing.allocator;
    const Lut = ArrayLookupTable(u8, u8);

    var lut = try Lut.init(allocator);
    defer lut.deinit(allocator);

    lut.fill(0);
    try std.testing.expectEqual(0, lut.get(1));
}

pub fn StructLookupTable(comptime lookup_table_types: []const type) type {
    comptime var field_names: [lookup_table_types.len][]const u8 = undefined;
    inline for (&field_names, 0..) |*field_name, index| field_name.* = std.mem.asBytes(&index);

    comptime var field_types: [lookup_table_types.len]type = undefined;
    inline for (&field_types, lookup_table_types) |*field_type, lookup_table_type| field_type.* = lookup_table_type;

    comptime var field_attributes: [lookup_table_types.len]std.builtin.Type.StructField.Attributes = undefined;
    inline for (&field_attributes) |*field_attribute| field_attribute.* = std.builtin.Type.StructField.Attributes{};

    const Container = @Struct(
        .auto,
        null,
        &field_names,
        &field_types,
        &field_attributes,
    );

    return struct {
        const Self = @This();
        container: Container,

        pub const SIZE = lookup_table_types.len;

        pub const empty = Self{ .container = undefined };

        pub fn get(self: *Self, comptime index: usize) *lookup_table_types[index] {
            const name = comptime std.mem.asBytes(&index);
            return &@field(self.container, name);
        }

        pub fn set(self: *Self, comptime index: usize, value: lookup_table_types[index]) void {
            const name = comptime std.mem.asBytes(&index);
            @field(self.container, name) = value;
        }
    };
}
