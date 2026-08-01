const std = @import("std");
const builtin = @import("builtin");

const firetrail = @import("root.zig");

const block_size = 8 * 1024 * 1024;
const frame_len_bytes = @sizeOf(u64);

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

    name: []u8,
    algorithm: Algorithm,
    mode: Mode,
    input: std.Io.File,
    output: std.Io.File,
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
        const input = if (std.mem.eql(u8, input_value, "-")) std.Io.File.stdin() else try cwd.openFile(io, input_value, .{});
        errdefer input.close(io);
        const output = if (std.mem.eql(u8, output_value, "-")) std.Io.File.stdout() else try cwd.createFile(io, output_value, .{});
        errdefer output.close(io);
        const import = if (parameters.import) |import| try cwd.openFile(io, import, .{}) else null;
        errdefer if (import) |file| file.close(io);
        const @"export" = if (parameters.@"export") |@"export"| try cwd.createFile(io, @"export", .{}) else null;
        errdefer if (@"export") |file| file.close(io);

        return .{ .name = name, .algorithm = algorithm, .mode = mode, .input = input, .output = output, .import = import, .@"export" = @"export" };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, io: std.Io) void {
        allocator.free(self.name);
        self.input.close(io);
        self.output.close(io);
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

                    var encoder = if (config.import) |file| blk: {
                        var import_reader = file.readerStreaming(io, &.{});
                        const import_slice = try import_reader.interface.allocRemaining(allocator, .unlimited);
                        defer allocator.free(import_slice);
                        break :blk try Encoder.fromSlice(allocator, import_slice);
                    } else try Encoder.init(allocator);
                    defer encoder.deinit(allocator);

                    const input_buffer = try allocator.alloc(u8, block_size);
                    defer allocator.free(input_buffer);
                    const output_data_buffer = try allocator.alloc(u8, Encoder.outputBufferBound(block_size));
                    defer allocator.free(output_data_buffer);

                    var input_reader = config.input.readerStreaming(io, input_buffer);

                    while (true) {
                        const input = input_reader.interface.peek(input_buffer.len) catch |err| switch (err) {
                            error.EndOfStream => input_reader.interface.buffered(),
                            else => return err,
                        };
                        if (input.len == 0) break;

                        const output_size = encoder.compressBlockToBuffer(input, output_data_buffer);
                        input_reader.interface.toss(input.len);
                        try config.output.writeStreamingAll(io, output_data_buffer[0..output_size]);
                    }

                    if (config.@"export") |@"export"| {
                        const slice = try encoder.toSlice(allocator);
                        defer allocator.free(slice);
                        try @"export".writeStreamingAll(io, slice);
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
                    const Encoder = switch (algorithm) {
                        .white => firetrail.white.Encoder,
                        .orange => firetrail.orange.Encoder,
                        .red => firetrail.red.Encoder,
                    };

                    var decoder = if (config.import) |file| blk: {
                        var import_reader = file.readerStreaming(io, &.{});
                        const import_slice = try import_reader.interface.allocRemaining(allocator, .unlimited);
                        defer allocator.free(import_slice);
                        break :blk try Decoder.fromSlice(allocator, import_slice);
                    } else try Decoder.init(allocator);
                    defer decoder.deinit(allocator);
                    const reader_buffer = try allocator.alloc(u8, Encoder.outputBufferBound(block_size));
                    defer allocator.free(reader_buffer);
                    const output_buffer = try allocator.alloc(u8, block_size);
                    defer allocator.free(output_buffer);

                    var input_reader = config.input.readerStreaming(io, reader_buffer);

                    while (true) {
                        _ = input_reader.interface.peekByte() catch |err| switch (err) {
                            error.EndOfStream => break,
                            else => return err,
                        };

                        const header = try input_reader.interface.peek(Decoder.size_bytes * 2);
                        const output_data_size = Decoder.exactOutputLength(header[0..Decoder.size_bytes]);
                        const input_data_size = Decoder.exactInputLength(header[Decoder.size_bytes..]);

                        if (output_data_size > output_buffer.len) return error.BlockTooLarge;
                        if (input_data_size > reader_buffer.len) return error.BlockTooLarge;

                        const block = try input_reader.interface.peek(input_data_size);
                        input_reader.interface.toss(input_data_size);

                        _ = decoder.decompressBlockToBuffer(block, output_buffer);
                        try config.output.writeStreamingAll(io, output_buffer[0..output_data_size]);
                    }

                    if (config.@"export") |@"export"| {
                        const slice = try decoder.toSlice(allocator);
                        defer allocator.free(slice);
                        try @"export".writeStreamingAll(io, slice);
                    }
                },
            }
        },
    }
}
