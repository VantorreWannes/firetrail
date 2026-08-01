const std = @import("std");
const builtin = @import("builtin");

const firetrail = @import("root.zig");

const Parameters = struct {
    const Self = @This();

    name: ?[]u8,
    algorithm: ?[]u8,
    mode: ?[]u8,
    input: ?[]u8,
    output: ?[]u8,
    import: ?[]u8,
    @"export": ?[]u8,

    fn findOption(arguments: []const [:0]const u8, flag: []const u8) ?usize {
        for (arguments, 0..) |arg, i| {
            if (std.mem.eql(u8, arg, flag)) return i;
        }
        return null;
    }

    pub fn init(allocator: std.mem.Allocator, args: std.process.Args) !Self {
        const arguments = try args.toSlice(allocator);
        defer allocator.free(arguments);

        const name_index: ?usize = if (arguments.len > 0) 0 else null;
        const algorithm_index: ?usize = if (arguments.len > 1) 1 else null;
        const mode_index: ?usize = if (arguments.len > 2) 2 else null;
        const input_index: ?usize = if (arguments.len > 3) 3 else null;
        const output_index: ?usize = if (arguments.len > 4) 4 else null;

        const import_option_index: ?usize = findOption(arguments, "--import");
        const export_option_index: ?usize = findOption(arguments, "--export");
        const import_index: ?usize = if (import_option_index) |index| if (index + 1 < arguments.len) index + 1 else null else null;
        const export_index: ?usize = if (export_option_index) |index| if (index + 1 < arguments.len) index + 1 else null else null;

        const name = if (name_index) |index| try allocator.dupe(u8, arguments[index]) else null;
        errdefer if (name) |value| allocator.free(value);
        const algorithm = if (algorithm_index) |index| try allocator.dupe(u8, arguments[index]) else null;
        errdefer if (algorithm) |value| allocator.free(value);
        const mode = if (mode_index) |index| try allocator.dupe(u8, arguments[index]) else null;
        errdefer if (mode) |value| allocator.free(value);
        const input = if (input_index) |index| try allocator.dupe(u8, arguments[index]) else null;
        errdefer if (input) |value| allocator.free(value);
        const output = if (output_index) |index| try allocator.dupe(u8, arguments[index]) else null;
        errdefer if (output) |value| allocator.free(value);
        const import = if (import_index) |index| try allocator.dupe(u8, arguments[index]) else null;
        errdefer if (import) |value| allocator.free(value);
        const @"export" = if (export_index) |index| try allocator.dupe(u8, arguments[index]) else null;
        errdefer if (@"export") |value| allocator.free(value);

        return Self{
            .name = name,
            .algorithm = algorithm,
            .mode = mode,
            .input = input,
            .output = output,
            .import = import,
            .@"export" = @"export",
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.name) |value| allocator.free(value);
        if (self.algorithm) |value| allocator.free(value);
        if (self.mode) |value| allocator.free(value);
        if (self.input) |value| allocator.free(value);
        if (self.output) |value| allocator.free(value);
        if (self.import) |value| allocator.free(value);
        if (self.@"export") |value| allocator.free(value);
    }
};
const Config = struct {
    const Self = @This();
    const alignment = std.heap.page_size_min;

    pub const Mode = enum {
        decode,
        encode,
    };

    pub const Algorithm = enum {
        white,
        orange,
        red,
    };

    pub const File = struct {
        file: std.Io.File,
        is_std: bool,
    };

    name: []u8,
    algorithm: Algorithm,
    mode: Mode,
    input: File,
    output: File,
    import: ?std.Io.File,
    @"export": ?std.Io.File,

    pub fn initFromParameters(allocator: std.mem.Allocator, io: std.Io, parameters: *const Parameters) !Self {
        const cwd = std.Io.Dir.cwd();
        const name_value = try if (parameters.name) |name| name else error.MissingArguments;
        const algorithm_value = try if (parameters.algorithm) |algorithm| algorithm else error.MissingArguments;
        const mode_value = try if (parameters.mode) |mode| mode else error.MissingArguments;
        const input_value = try if (parameters.input) |input| input else error.MissingArguments;
        const output_value = try if (parameters.output) |output| output else error.MissingArguments;

        const name = try allocator.dupe(u8, name_value);
        errdefer allocator.free(name);
        const algorithm = try if (std.mem.eql(u8, algorithm_value, "white")) Algorithm.white else if (std.mem.eql(u8, algorithm_value, "orange")) Algorithm.orange else if (std.mem.eql(u8, algorithm_value, "red")) Algorithm.red else error.InvalidAlgorithm;
        const mode = try if (std.mem.eql(u8, mode_value, "encode")) Mode.encode else if (std.mem.eql(u8, mode_value, "decode")) Mode.decode else error.InvalidMode;
        const input_is_std = std.mem.eql(u8, input_value, "-");
        const input = File{ .file = if (input_is_std) std.Io.File.stdin() else try cwd.openFile(io, input_value, .{}), .is_std = input_is_std };
        errdefer if (!input.is_std) input.file.close(io);
        const output_is_std = std.mem.eql(u8, output_value, "-");
        const output = File{ .file = if (output_is_std) std.Io.File.stdout() else try cwd.createFile(io, output_value, .{ .read = true }), .is_std = output_is_std };
        errdefer if (!output.is_std) output.file.close(io);
        const import = if (parameters.import) |import| try cwd.openFile(io, import, .{}) else null;
        errdefer if (import) |file| file.close(io);
        const @"export" = if (parameters.@"export") |@"export"| try cwd.createFile(io, @"export", .{ .read = true }) else null;
        errdefer if (@"export") |file| file.close(io);

        return .{ .name = name, .algorithm = algorithm, .mode = mode, .input = input, .output = output, .import = import, .@"export" = @"export" };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, io: std.Io) void {
        allocator.free(self.name);
        if (!self.input.is_std) self.input.file.close(io);
        if (!self.output.is_std) self.output.file.close(io);
        if (self.import) |file| file.close(io);
        if (self.@"export") |file| file.close(io);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = init.minimal.args;
    var parameters = try Parameters.init(allocator, args);
    defer parameters.deinit(allocator);
    var config = try Config.initFromParameters(allocator, io, &parameters);
    defer config.deinit(allocator, io);

    switch (config.mode) {
        .encode => {
            switch (config.algorithm) {
                inline else => |algorithm| {
                    const Encoder = switch (algorithm) {
                        .white => firetrail.white.Encoder,
                        .orange => firetrail.orange.Encoder,
                        .red => firetrail.red.Encoder,
                    };

                    var encoder = try if (config.import) |import_file| blk: {
                        const import_size = try import_file.length(io);
                        var import = try import_file.createMemoryMap(io, .{
                            .populate = false,
                            .len = import_size,
                            .protection = .{ .read = true },
                        });
                        defer import.destroy(io);
                        break :blk Encoder.fromSlice(allocator, import.memory);
                    } else Encoder.init(allocator);
                    defer encoder.deinit(allocator);

                    const input_size = try config.input.file.length(io);
                    const bound = Encoder.outputBufferBound(input_size);

                    var output_size: usize = undefined;
                    if (config.input.is_std) {
                        var reader = config.input.file.readerStreaming(io, &.{});
                        const input_buffer = try reader.interface.allocRemaining(allocator, .unlimited);
                        defer allocator.free(input_buffer);

                        const output_buffer = try allocator.alloc(u8, bound);
                        defer allocator.free(output_buffer);
                        output_size = encoder.compressBlockToBuffer(input_buffer, output_buffer);
                        try config.output.file.writeStreamingAll(io, output_buffer[0..output_size]);
                    } else if (config.output.is_std) {
                        var input = try config.input.file.createMemoryMap(io, .{
                            .populate = false,
                            .len = input_size,
                            .protection = .{ .read = true },
                        });
                        defer input.destroy(io);

                        const output_buffer = try allocator.alloc(u8, bound);
                        defer allocator.free(output_buffer);
                        output_size = encoder.compressBlockToBuffer(input.memory, output_buffer);
                        try config.output.file.writeStreamingAll(io, output_buffer[0..output_size]);
                    } else {
                        var input = try config.input.file.createMemoryMap(io, .{
                            .populate = false,
                            .len = input_size,
                            .protection = .{ .read = true },
                        });
                        defer input.destroy(io);

                        try config.output.file.setLength(io, bound);
                        var output = try config.output.file.createMemoryMap(io, .{
                            .populate = false,
                            .len = bound,
                            .protection = .{ .read = true, .write = true },
                        });
                        output_size = encoder.compressBlockToBuffer(input.memory, output.memory);
                        output.destroy(io);
                        try config.output.file.setLength(io, output_size);
                    }

                    if (config.@"export") |export_file| {
                        const slice = try encoder.toSlice(allocator);
                        defer allocator.free(slice);
                        try export_file.setLength(io, slice.len);
                        var @"export" = try export_file.createMemoryMap(io, .{
                            .populate = false,
                            .len = slice.len,
                            .protection = .{ .read = true, .write = true },
                        });
                        @memcpy(@"export".memory, slice);
                        @"export".destroy(io);
                    }
                },
            }
        },
        .decode => {
            switch (config.algorithm) {
                inline else => |algorithm| {
                    const Decoder = switch (algorithm) {
                        .white => firetrail.white.Decoder,
                        .orange => firetrail.orange.Decoder,
                        .red => firetrail.red.Decoder,
                    };

                    var decoder = try if (config.import) |import_file| blk: {
                        const import_size = try import_file.length(io);
                        var import = try import_file.createMemoryMap(io, .{
                            .populate = false,
                            .len = import_size,
                            .protection = .{ .read = true },
                        });
                        defer import.destroy(io);
                        break :blk Decoder.fromSlice(allocator, import.memory);
                    } else Decoder.init(allocator);
                    defer decoder.deinit(allocator);

                    const input_size = try config.input.file.length(io);
                    var output_size: usize = undefined;
                    if (config.input.is_std) {
                        var reader = config.input.file.readerStreaming(io, &.{});
                        const input_buffer = try reader.interface.allocRemaining(allocator, .unlimited);
                        defer allocator.free(input_buffer);

                        const output_buffer = try allocator.alloc(u8, Decoder.exactOutputLength(input_buffer));
                        defer allocator.free(output_buffer);
                        output_size = decoder.decompressBlockToBuffer(input_buffer, output_buffer);
                        try config.output.file.writeStreamingAll(io, output_buffer[0..output_size]);
                    } else if (config.output.is_std) {
                        var input = try config.input.file.createMemoryMap(io, .{
                            .populate = false,
                            .len = input_size,
                            .protection = .{ .read = true },
                        });
                        defer input.destroy(io);

                        const output_buffer = try allocator.alloc(u8, Decoder.exactOutputLength(input.memory));
                        defer allocator.free(output_buffer);
                        output_size = decoder.decompressBlockToBuffer(input.memory, output_buffer);
                        try config.output.file.writeStreamingAll(io, output_buffer[0..output_size]);
                    } else {
                        var input = try config.input.file.createMemoryMap(io, .{
                            .populate = false,
                            .len = input_size,
                            .protection = .{ .read = true },
                        });
                        defer input.destroy(io);

                        const bound = Decoder.exactOutputLength(input.memory);
                        try config.output.file.setLength(io, bound);
                        var output = try config.output.file.createMemoryMap(io, .{
                            .populate = false,
                            .len = bound,
                            .protection = .{ .read = true, .write = true },
                        });
                        output_size = decoder.decompressBlockToBuffer(input.memory, output.memory);
                        output.destroy(io);
                        try config.output.file.setLength(io, output_size);
                    }

                    if (config.@"export") |export_file| {
                        const slice = try decoder.toSlice(allocator);
                        defer allocator.free(slice);
                        try export_file.setLength(io, slice.len);
                        var @"export" = try export_file.createMemoryMap(io, .{
                            .populate = false,
                            .len = slice.len,
                            .protection = .{ .read = true, .write = true },
                        });
                        @memcpy(@"export".memory, slice);
                        @"export".destroy(io);
                    }
                },
            }
        },
    }
}
