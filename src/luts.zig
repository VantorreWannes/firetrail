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
    inline for (&field_names, 0..) |*name, i| {
        name.* = std.fmt.comptimePrint("{d}", .{i});
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
            return &@field(self.container, std.fmt.comptimePrint("{d}", .{index}));
        }

        pub fn set(self: *Self, comptime index: usize, value: lookup_table_types[index]) void {
            @field(self.container, std.fmt.comptimePrint("{d}", .{index})) = value;
        }
    };
}

pub const EvictFn = fn (cursor: u8, ways: u8) u8;

pub fn roundRobin(cursor: u8, ways: u8) u8 {
    return (cursor +% 1) & (ways - 1);
}

pub fn SetAssociativeLookupTable(
    comptime Key: type,
    comptime Value: type,
    comptime ways_log2: comptime_int,
    comptime evict: EvictFn,
) type {
    const key_bits = @bitSizeOf(Key);
    if (@typeInfo(Key) != .int or @typeInfo(Key).int.signedness != .unsigned)
        @compileError("Key must be an unsigned integer type");
    if (ways_log2 < 0 or ways_log2 > 8)
        @compileError("ways_log2 must be in 0..8");
    if (ways_log2 >= key_bits)
        @compileError("ways_log2 must be < @bitSizeOf(Key) to keep at least one set");

    return struct {
        const Self = @This();

        const ways: usize = 1 << ways_log2;
        const sets: usize = (1 << key_bits) / ways;
        const set_mask: usize = sets - 1;
        const way_mask: u8 = ways - 1;
        const total: usize = sets * ways;

        pub const K = Key;
        pub const V = Value;

        mem: []align(@alignOf(Value)) u8,
        table: []Value,
        cursors: []u8,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const table_bytes = total * @sizeOf(Value);
            const padded_table = std.mem.alignForward(usize, table_bytes, @alignOf(Value));
            const total_bytes = padded_table + sets;

            const raw = try allocator.alignedAlloc(
                u8,
                std.mem.Alignment.fromByteUnits(@alignOf(Value)),
                total_bytes,
            );
            @memset(raw, 0);
            return .{
                .mem = raw,
                .table = std.mem.bytesAsSlice(Value, raw[0..table_bytes]),
                .cursors = raw[padded_table .. padded_table + sets],
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.mem);
            self.* = undefined;
        }

        pub fn fill(self: *Self, value: Value) void {
            @memset(self.table, value);
            @memset(self.cursors, 0);
        }

        pub inline fn insert(self: *Self, key: Key, value: Value) void {
            const set = @as(usize, key) & set_mask;
            const cursor = self.cursors[set];
            self.table[set * ways + cursor] = value;
            self.cursors[set] = evict(cursor, way_mask + 1);
        }

        pub inline fn lookup(self: *const Self, key: Key, target: Value) ?Value {
            const base = (@as(usize, key) & set_mask) * ways;
            inline for (0..ways) |way| {
                if (self.table[base + way] == target) return target;
            }
            return null;
        }
    };
}

pub fn DefaultSetAssociativeLookupTable(
    comptime Key: type,
    comptime Value: type,
    comptime ways_log2: comptime_int,
) type {
    return SetAssociativeLookupTable(Key, Value, ways_log2, roundRobin);
}

const testing = std.testing;

test "associative: init + deinit" {
    const Lut = DefaultSetAssociativeLookupTable(u16, u64, 2);
    var lut = try Lut.init(testing.allocator);
    defer lut.deinit(testing.allocator);
}

test "associative: miss then hit" {
    const Lut = DefaultSetAssociativeLookupTable(u8, u64, 2);
    var lut = try Lut.init(testing.allocator);
    defer lut.deinit(testing.allocator);

    try testing.expectEqual(@as(?u64, null), lut.lookup(7, 0xABCD));
    lut.insert(7, 0xABCD);
    try testing.expectEqual(@as(?u64, 0xABCD), lut.lookup(7, 0xABCD));
}

test "associative: ways absorb conflicts" {
    const Lut = DefaultSetAssociativeLookupTable(u8, u64, 2);
    var lut = try Lut.init(testing.allocator);
    defer lut.deinit(testing.allocator);

    lut.insert(0, 0x10);
    lut.insert(0, 0x20);
    lut.insert(0, 0x30);
    lut.insert(0, 0x40);

    try testing.expect(lut.lookup(0, 0x10) != null);
    try testing.expect(lut.lookup(0, 0x40) != null);
}

test "associative: custom eviction policy" {
    const alwaysZero = struct {
        fn evict(_: u8, _: u8) u8 {
            return 0;
        }
    }.evict;

    const Lut = SetAssociativeLookupTable(u8, u64, 2, alwaysZero);
    var lut = try Lut.init(testing.allocator);
    defer lut.deinit(testing.allocator);

    lut.insert(0, 0xAA);
    lut.insert(0, 0xBB);
    try testing.expectEqual(@as(?u64, null), lut.lookup(0, 0xAA));
    try testing.expectEqual(@as(?u64, 0xBB), lut.lookup(0, 0xBB));
}
