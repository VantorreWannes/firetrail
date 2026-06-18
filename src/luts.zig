const std = @import("std");

pub fn ArrayLookupTable(comptime Key: type, comptime Value: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        pub const K = Key;
        pub const V = Value;

        table: []Value,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{ .table = try allocator.alloc(Value, size+1) };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.table);
            self.* = undefined;
        }

        pub fn fill(self: *Self, value: Value) void {
            @memset(self.table, value);
        }

        pub inline fn get(self: *const Self, key: Key) Value {
            return self.table[key % size];
        }

        pub inline fn set(self: *Self, key: Key, value: Value) void {
            self.table[key % size] = value;
        }
    };
}

test "init + deinit" {
    const Lut = ArrayLookupTable(u16, u32, 1);
    var lut = try Lut.init(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
}

test "set" {
    const Lut = ArrayLookupTable(u8, u8, 1);
    var lut = try Lut.init(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
    lut.set(0, 0);
    try std.testing.expectEqual(@as(u8, 0), lut.get(0));
}

test "get" {
    const Lut = ArrayLookupTable(u8, u8, 1);
    var lut = try Lut.init(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
    lut.set(0, 0);
    try std.testing.expectEqual(@as(u8, 0), lut.get(0));
}

test "fill" {
    const Lut = ArrayLookupTable(u8, u8, 2);
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

        pub fn get(self: *const Self, comptime index: usize) *lookup_table_types[index] {
            const field_name = comptime std.mem.asBytes(index);
            return &@field(self.container, field_name);
        }

        pub fn set(self: *Self, comptime index: usize, value: lookup_table_types[index]) void {
            const field_name = comptime std.mem.asBytes(index);
            @field(self.container, field_name) = value;
        }
    };
}

pub fn FreqLookupTable(
    comptime Key: type,
    comptime Value: type,
    comptime Count: type,
) type {
    if (@typeInfo(Key) != .int) @compileError("Key must be an integer type");
    if (@typeInfo(Count) != .int) @compileError("Count must be an integer type");

    return struct {
        const Self = @This();
        const size = 1 << @bitSizeOf(Key);
        const max_count = std.math.maxInt(Count);

        pub const K = Key;
        pub const V = Value;
        pub const C = Count;

        values: []Value,
        slot_counts: []Count,
        freq: []Count,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const values = try allocator.alloc(Value, size);
            errdefer allocator.free(values);

            const slot_counts = try allocator.alloc(Count, size);
            errdefer allocator.free(slot_counts);

            const freq = try allocator.alloc(Count, size);

            return .{
                .values = values,
                .slot_counts = slot_counts,
                .freq = freq,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.values);
            allocator.free(self.slot_counts);
            allocator.free(self.freq);
            self.* = undefined;
        }

        pub fn fill(self: *Self, value: Value) void {
            @memset(self.values, value);
            @memset(self.slot_counts, 0);
            @memset(self.freq, 0);
        }

        pub inline fn get(self: *const Self, key: Key) Value {
            return self.values[key];
        }

        inline fn getCount(self: *const Self, key: Key) Count {
            return self.slot_counts[key];
        }

        pub inline fn set(self: *Self, key: Key, value: Value) void {
            const new_freq = self.freq[key] +| 1;
            self.freq[key] = new_freq;

            if (new_freq > self.slot_counts[key]) {
                self.values[key] = value;
                self.slot_counts[key] = new_freq;
            }
        }
    };
}
