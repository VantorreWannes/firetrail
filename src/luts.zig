const std = @import("std");

fn LookupTable(comptime Key: type, comptime Value: type) type {
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

        test init {
            const allocator = std.testing.allocator;
            var table = try Self.init(allocator);
            defer table.deinit(allocator);
        }

        test fill {
            const allocator = std.testing.allocator;
            var table = try Self.init(allocator);
            defer table.deinit(allocator);

            const expected = 0;
            table.fill(expected);
            for (table.table) |value| try std.testing.expectEqual(expected, value);
        }

        test get {
            const allocator = std.testing.allocator;
            var table = try Self.init(allocator);
            defer table.deinit(allocator);

            const expected = 0;
            table.fill(expected);

            for (0..SIZE) |index| {
                const value = table.get(@intCast(index));
                try std.testing.expectEqual(expected, value);
            }
        }

        test set {
            const allocator = std.testing.allocator;
            var table = try Self.init(allocator);
            defer table.deinit(allocator);

            const expected = 0;

            for (0..SIZE) |index| {
                table.set(@intCast(index), expected);
                const value = table.get(@intCast(index));
                try std.testing.expectEqual(expected, value);
            }
        }
    };
}

test {
    {
        std.testing.refAllDecls(LookupTable(u8, u8));
        std.testing.refAllDecls(LookupTable(u8, u16));
        std.testing.refAllDecls(LookupTable(u8, u32));
        std.testing.refAllDecls(LookupTable(u8, u64));
        std.testing.refAllDecls(LookupTable(u8, u128));
        std.testing.refAllDecls(LookupTable(u8, i8));
        std.testing.refAllDecls(LookupTable(u8, i16));
        std.testing.refAllDecls(LookupTable(u8, i32));
        std.testing.refAllDecls(LookupTable(u8, i64));
        std.testing.refAllDecls(LookupTable(u8, u128));
    }
    {
        std.testing.refAllDecls(LookupTable(u16, u8));
        std.testing.refAllDecls(LookupTable(u16, u16));
        std.testing.refAllDecls(LookupTable(u16, u32));
        std.testing.refAllDecls(LookupTable(u16, u64));
        std.testing.refAllDecls(LookupTable(u16, i8));
        std.testing.refAllDecls(LookupTable(u16, i16));
        std.testing.refAllDecls(LookupTable(u16, i32));
        std.testing.refAllDecls(LookupTable(u16, i64));
    }
    {
        std.testing.refAllDecls(LookupTable(u32, u8));
        std.testing.refAllDecls(LookupTable(u32, u16));
        std.testing.refAllDecls(LookupTable(u32, i8));
        std.testing.refAllDecls(LookupTable(u32, i16));
    }
}
