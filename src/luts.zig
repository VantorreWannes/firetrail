const std = @import("std");

pub fn LookupTable(comptime Key: type, comptime Value: type) type {
    return struct {
        const Self = @This();
        const SIZE = 1 << @bitSizeOf(Key);

        table: []Value,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const table = try allocator.alloc(Value, SIZE);
            return Self{ .table = table };
        }

        pub fn fill(self: *Self, value: Value) void {
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