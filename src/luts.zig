const std = @import("std");

pub fn ArrayLookupTable(comptime Key: type, comptime Value: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        pub const K = Key;
        pub const V = Value;

        table: []Value,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{ .table = try allocator.alloc(Value, size + 1) };
        }

        pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: []const u8) !Self {
            return Self{ .table = try allocator.dupe(Value, @alignCast(std.mem.bytesAsSlice(Value, buffer))) };
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

        pub fn exportBuffer(self: *const Self) ![]u8 {
            return std.mem.sliceAsBytes(self.table);
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
    comptime size: usize,
) type {
    if (@typeInfo(Key) != .int) @compileError("Key must be an integer type");
    if (@typeInfo(Count) != .int) @compileError("Count must be an integer type");

    return struct {
        const Self = @This();

        pub const K = Key;
        pub const V = Value;
        pub const C = Count;

        const values_bytes = size * @sizeOf(Value);
        const slot_counts_bytes = size * @sizeOf(Count);
        const freq_bytes = size * @sizeOf(Count);
        const total_bytes = values_bytes + slot_counts_bytes + freq_bytes;

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

        pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: []const u8) !Self {
            if (buffer.len != total_bytes) return error.InvalidTableSize;

            var self = try Self.init(allocator);
            errdefer self.deinit(allocator);

            @memcpy(std.mem.sliceAsBytes(self.values), buffer[0..values_bytes]);
            @memcpy(std.mem.sliceAsBytes(self.slot_counts), buffer[values_bytes..][0..slot_counts_bytes]);
            @memcpy(std.mem.sliceAsBytes(self.freq), buffer[values_bytes + slot_counts_bytes ..][0..freq_bytes]);

            return self;
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
            return self.values[key % size];
        }

        pub inline fn set(self: *Self, key: Key, value: Value) void {
            const index = key % size;
            const new_freq = self.freq[index] +| 1;
            self.freq[index] = new_freq;

            if (new_freq > self.slot_counts[index]) {
                self.values[index] = value;
                self.slot_counts[index] = new_freq;
            }
        }

        pub fn exportBuffer(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
            const buffer = try allocator.alloc(u8, total_bytes);

            @memcpy(buffer[0..values_bytes], std.mem.sliceAsBytes(self.values));
            @memcpy(buffer[values_bytes..][0..slot_counts_bytes], std.mem.sliceAsBytes(self.slot_counts));
            @memcpy(buffer[values_bytes + slot_counts_bytes ..][0..freq_bytes], std.mem.sliceAsBytes(self.freq));

            return buffer;
        }
    };
}

pub fn HashValueMap(comptime Hash: type, comptime Value: type) type {
    const info = @typeInfo(Hash);
    comptime if (info != .int or info.int.signedness != .unsigned)
        @compileError("HashValueMap requires an unsigned integer key type, got: " ++ @typeName(Hash));

    return struct {
        const Self = @This();

        keys: []?Hash,
        data: []Value,
        count: usize,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return try Self.initWithCapacity(allocator, 0);
        }

        pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !Self {
            const keys = try allocator.alloc(?Hash, capacity);
            errdefer allocator.free(keys);
            const data = try allocator.alloc(Value, capacity);
            return .{ .keys = keys, .data = data, .count = capacity };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.keys);
            allocator.free(self.data);
            self.* = undefined;
        }

        inline fn shouldGrow(self: *const Self) bool {
            return self.count * 2 >= self.keys.len;
        }

        inline fn slotFor(keys: []?Hash, hash: Hash) usize {
            var index = hash % keys.len;
            while (keys[index] != null and keys[index] != hash)
                index = (index +% 1) % keys.len;
            return index;
        }

        fn grow(self: *Self, allocator: std.mem.Allocator) !void {
            const new_len = @max(self.keys.len, 1) * 2;

            var new_keys = try allocator.alloc(?Hash, new_len);
            errdefer allocator.free(new_keys);
            var new_data = try allocator.alloc(Value, new_len);
            errdefer allocator.free(new_data);

            @memset(new_keys, null);

            for (self.keys, self.data) |maybe_hash, value| {
                if (maybe_hash) |hash| {
                    const index = slotFor(new_keys, hash);
                    new_keys[index] = hash;
                    new_data[index] = value;
                }
            }

            allocator.free(self.keys);
            allocator.free(self.data);
            self.keys = new_keys;
            self.data = new_data;
        }

        pub fn set(self: *Self, allocator: std.mem.Allocator, hash: Hash, value: Value) !void {
            if (self.shouldGrow()) try self.grow(allocator);
            std.debug.assert(self.keys.len > 0);

            const index = slotFor(self.keys, hash);
            if (self.keys[index] == null) self.count += 1;
            self.keys[index] = hash;
            self.data[index] = value;
        }

        pub fn contains(self: *const Self, hash: Hash) bool {
            if (self.keys.len == 0) return false;
            const index = slotFor(self.keys, hash);
            return self.keys[index] != null;
        }

        pub fn get(self: *const Self, hash: Hash) ?Value {
            if (self.keys.len == 0) return null;
            const index = slotFor(self.keys, hash);
            if (self.keys[index] == null) return null;
            return self.data[index];
        }
    };
}

const testing = std.testing;

test "empty map" {
    var map = try HashValueMap(u32, u32).init(testing.allocator);
    defer map.deinit(testing.allocator);

    try testing.expectEqual(0, map.count);
    try testing.expect(!map.contains(1));
    try testing.expect(map.get(1) == null);
}

test "set and get" {
    var map = try HashValueMap(u32, u32).init(testing.allocator);
    defer map.deinit(testing.allocator);

    try map.set(testing.allocator, 7, 700);

    try testing.expectEqual(1, map.count);
    try testing.expect(map.contains(7));
    try testing.expectEqual(700, map.get(7).?);
    try testing.expect(map.get(8) == null);
}

test "set overwrites existing key without changing count" {
    var map = try HashValueMap(u32, u32).init(testing.allocator);
    defer map.deinit(testing.allocator);

    try map.set(testing.allocator, 7, 700);
    try map.set(testing.allocator, 7, 701);

    try testing.expectEqual(701, map.get(7).?);
    try testing.expectEqual(1, map.count);
}

test "key 0 is valid" {
    var map = try HashValueMap(u32, u32).init(testing.allocator);
    defer map.deinit(testing.allocator);

    try testing.expect(!map.contains(0));
    try map.set(testing.allocator, 0, 123);
    try testing.expect(map.contains(0));
    try testing.expectEqual(123, map.get(0).?);
}

test "many inserts survive multiple grows" {
    var map = try HashValueMap(u32, u64).init(testing.allocator);
    defer map.deinit(testing.allocator);

    for (0..100) |i| {
        try map.set(testing.allocator, @intCast(i), @as(u64, i) * 3);
    }

    try testing.expectEqual(100, map.count);
    for (0..100) |i| {
        try testing.expectEqual(@as(u64, i) * 3, map.get(@intCast(i)).?);
    }
    try testing.expect(!map.contains(100));
}

test "colliding keys coexist" {
    var map = try HashValueMap(u32, u32).init(testing.allocator);
    defer map.deinit(testing.allocator);

    try map.set(testing.allocator, 0, 10);
    try map.set(testing.allocator, 1, 20);
    try map.set(testing.allocator, 2, 30);
    try map.set(testing.allocator, 8, 80);

    try testing.expectEqual(10, map.get(0).?);
    try testing.expectEqual(80, map.get(8).?);
}

test "overwrite after growth keeps neighbours intact" {
    var map = try HashValueMap(u32, u32).init(testing.allocator);
    defer map.deinit(testing.allocator);

    for (0..50) |i| try map.set(testing.allocator, @intCast(i), @intCast(i));

    try map.set(testing.allocator, 25, 9999);

    try testing.expectEqual(9999, map.get(25).?);
    try testing.expectEqual(50, map.count);
    try testing.expectEqual(24, map.get(24).?);
    try testing.expectEqual(26, map.get(26).?);
}

pub fn ManyChoiceTable(comptime Key: type, comptime Value: type, comptime size: usize, comptime choices: usize) type {
    return struct {
        const Self = @This();

        pub const K = Key;
        pub const V = Value;

        table: []Value,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{ .table = try allocator.alloc(Value, size) };
        }

        pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: []const u8) !Self {
            if (buffer.len != size * @sizeOf(Value)) return error.InvalidTableSize;
            return .{ .table = try allocator.dupe(Value, @alignCast(std.mem.bytesAsSlice(Value, buffer))) };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.table);
            self.* = undefined;
        }

        pub fn fill(self: *Self, value: Value) void {
            @memset(self.table, value);
        }

        pub inline fn probe(self: *Self, hashes: [choices]Key, word: Value) ?Key {
            inline for (hashes) |h| {
                if (self.table[h] == word) return h;
            }
            self.table[hashes[0]] = word;
            return null;
        }


        pub inline fn get(self: *const Self, key: Key) Value {
            return self.table[key];
        }

        pub fn exportBuffer(self: *const Self) ![]u8 {
            return std.mem.sliceAsBytes(self.table);
        }
    };
}
