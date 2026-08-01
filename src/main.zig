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

    name: []u8,
    algorithm: Algorithm,
    mode: Mode,
    input: std.Io.File.MemoryMap,
    output: std.Io.File,
    import: ?std.Io.File.MemoryMap,
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
        const input_file = if (std.mem.eql(u8, input_value, "-")) std.Io.File.stdin() else try cwd.openFile(io, input_value, .{});
        errdefer input_file.close(io);
        const output_file = if (std.mem.eql(u8, output_value, "-")) std.Io.File.stdout() else try cwd.createFile(io, output_value, .{});
        errdefer output_file.close(io);
        const import_file = if (parameters.import) |import| try cwd.openFile(io, import, .{}) else null;
        errdefer if (import_file) |file| file.close(io);
        const export_file = if (parameters.@"export") |@"export"| try cwd.createFile(io, @"export", .{}) else null;
        errdefer if (export_file) |file| file.close(io);
        const input_file_size = try input_file.length(io);
        var input = try input_file.createMemoryMap(io, .{
            .populate = false,
            .len = input_file_size,
            .protection = .{ .read = true },
        });
        errdefer input.destroy(io);
        const output = output_file;
        errdefer output.close(io);
        const import_file_size = if (import_file) |file| try file.length(io) else null;
        var import = if (import_file) |file| try file.createMemoryMap(io, .{
            .populate = false,
            .len = import_file_size orelse 0,
            .protection = .{ .read = true },
        }) else null;
        errdefer if (import) |*file| file.destroy(io);
        const @"export" = export_file;
        errdefer if (@"export") |file| file.close(io);

        return .{ .name = name, .algorithm = algorithm, .mode = mode, .input = input, .output = output, .import = import, .@"export" = @"export" };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator, io: std.Io) void {
        allocator.free(self.name);
        self.input.destroy(io);
        self.output.close(io);
        if (self.import) |*import| import.destroy(io);
        if (self.@"export") |*@"export"| @"export".close(io);
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

                    var encoder = try if (config.import) |import| Encoder.fromSlice(allocator, import.memory) else Encoder.init(allocator);
                    defer encoder.deinit(allocator);

                    const input = config.input;
                    const input_size = try input.file.length(io);
                    const output_buffer = try allocator.alloc(u8, Encoder.outputBufferBound(input_size));
                    defer allocator.free(output_buffer);
                    const output_size = encoder.compressBlockToBuffer(input.memory, output_buffer);
                    try config.output.writeStreamingAll(io, output_buffer[0..output_size]);

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

                    var decoder = try Decoder.init(allocator);
                    defer decoder.deinit(allocator);
                },
            }
        },
    }
}

// const Config = struct {
//     algorithm: Algorithm,
//     mode: Mode,
//     input_stream: std.Io.File,
//     output_stream: std.Io.File,
//     import_stream: ?std.Io.File,
//     export_stream: ?std.Io.File,

//     /// Parses command-line arguments and opens the corresponding streams.
//     ///
//     /// Expects: `<algorithm> <--encode|-e|--decode|-d> <input> <output> [--import <lut_file>] [--export <lut_file>]`.
//     /// Passing `-` for a path selects stdin/stdout respectively.
//     pub fn initFromArgs(allocator: std.mem.Allocator, io: std.Io, args: std.process.Args) !Config {
//         const args_slice = try args.toSlice(allocator);
//         errdefer allocator.free(args_slice);

//         if (args_slice.len < 5) {
//             std.debug.print("Usage: {s} {{white|orange|red}} {{--encode|-e|--decode|-d}} <input> <output> [--import <lut_file>] [--export <lut_file>]\n", .{args_slice[0]});
//             return error.MissingArguments;
//         }

//         const algorithm = if (std.mem.eql(u8, args_slice[1], "white"))
//             Algorithm.white
//         else if (std.mem.eql(u8, args_slice[1], "orange"))
//             Algorithm.orange
//         else if (std.mem.eql(u8, args_slice[1], "red"))
//             Algorithm.red
//         else {
//             std.debug.print("Invalid algorithm: {s}\n", .{args_slice[1]});
//             return error.InvalidAlgorithm;
//         };

//         const mode = if (std.mem.eql(u8, args_slice[2], "--encode") or std.mem.eql(u8, args_slice[2], "-e"))
//             Mode.encode
//         else if (std.mem.eql(u8, args_slice[2], "--decode") or std.mem.eql(u8, args_slice[2], "-d"))
//             Mode.decode
//         else {
//             std.debug.print("Invalid mode: {s}\n", .{args_slice[2]});
//             return error.InvalidMode;
//         };

//         const input_path = args_slice[3];
//         const output_path = args_slice[4];

//         if (std.mem.eql(u8, input_path, output_path)) {
//             std.debug.print("Input and output paths must differ\n", .{});
//             return error.InputEqualsOutput;
//         }

//         const cwd = std.Io.Dir.cwd();

//         const input_stream = if (std.mem.eql(u8, input_path, "-")) std.Io.File.stdin() else try cwd.openFile(io, input_path, .{});
//         const output_stream = if (std.mem.eql(u8, output_path, "-")) std.Io.File.stdout() else try cwd.createFile(io, output_path, .{});

//         var import_stream: ?std.Io.File = null;
//         var export_stream: ?std.Io.File = null;

//         var i: usize = 5;
//         while (i < args_slice.len) {
//             if (std.mem.eql(u8, args_slice[i], "--import") and i + 1 < args_slice.len) {
//                 const path = args_slice[i + 1];
//                 import_stream = if (std.mem.eql(u8, path, "-")) std.Io.File.stdin() else try cwd.openFile(io, path, .{});
//                 i += 2;
//             } else if (std.mem.eql(u8, args_slice[i], "--export") and i + 1 < args_slice.len) {
//                 const path = args_slice[i + 1];
//                 export_stream = if (std.mem.eql(u8, path, "-")) std.Io.File.stdout() else try cwd.createFile(io, path, .{});
//                 i += 2;
//             } else {
//                 std.debug.print("Unknown argument: {s}\n", .{args_slice[i]});
//                 return error.InvalidArguments;
//             }
//         }

//         return Config{
//             .algorithm = algorithm,
//             .mode = mode,
//             .input_stream = input_stream,
//             .output_stream = output_stream,
//             .import_stream = import_stream,
//             .export_stream = export_stream,
//         };
//     }

//     /// Closes all streams opened by `initFromArgs`.
//     pub fn deinit(self: *Config, allocator: std.mem.Allocator, io: std.Io) void {
//         _ = allocator;
//         self.input_stream.close(io);
//         self.output_stream.close(io);
//         if (self.import_stream) |stream| stream.close(io);
//         if (self.export_stream) |stream| stream.close(io);
//     }
// };

// const block_size = 1024 * 1024 * 32;

// /// An input source yielding blocks of at most `block_size` bytes.
// ///
// /// Regular files are memory-mapped and sliced without copying; other streams
// /// (stdin, pipes) are read into a reusable buffer.
// const Source = struct {
//     mapped: ?[]align(std.heap.page_size_min) const u8 = null,
//     buffer: []u8 = &.{},
//     reader: std.Io.File.Reader = undefined,
//     offset: usize = 0,

//     /// Opens `file` as a source, memory-mapping it when possible.
//     pub fn init(allocator: std.mem.Allocator, io: std.Io, file: std.Io.File) !Source {
//         if (file.stat(io)) |st| {
//             if (st.kind == .file and st.size > 0) {
//                 const mapped = std.posix.mmap(null, st.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0) catch null;
//                 if (mapped) |m| return .{ .mapped = m };
//             }
//         } else |_| {}

//         const buffer = try allocator.alloc(u8, block_size);
//         var self = Source{ .buffer = buffer };
//         self.reader = file.reader(io, buffer);
//         return self;
//     }

//     /// Releases the mapping or buffer.
//     pub fn deinit(self: *Source, allocator: std.mem.Allocator) void {
//         if (self.mapped) |m| std.posix.munmap(@constCast(m));
//         if (self.buffer.len != 0) allocator.free(self.buffer);
//         self.* = undefined;
//     }

//     /// Returns the full input when it fits in one block, `null` otherwise.
//     /// Used by the decoder, whose blocks carry their own boundaries.
//     pub fn whole(self: *Source) ?[]const u8 {
//         const data = self.mapped orelse return null;
//         return if (data.len <= block_size) data else null;
//     }

//     /// Returns the next chunk of input (up to `block_size` bytes), or `null` at end of input.
//     pub fn nextBlock(self: *Source) !?[]const u8 {
//         if (self.mapped) |m| {
//             if (self.offset >= m.len) return null;
//             const end = @min(self.offset + block_size, m.len);
//             defer self.offset = end;
//             return m[self.offset..end];
//         }
//         const n = try self.reader.interface.readSliceShort(self.buffer);
//         return if (n == 0) null else self.buffer[0..n];
//     }
// };

// /// Compresses blocks from `source` to `writer`, exporting the dictionary when `export_stream` is set.
// fn encode(
//     comptime Encoder: type,
//     allocator: std.mem.Allocator,
//     io: std.Io,
//     config: *const Config,
//     source: *Source,
//     writer: *std.Io.Writer,
//     write_buffer: []u8,
// ) !void {
//     var encoder = if (config.import_stream) |import_stream| encoder: {
//         var reader = import_stream.reader(io, write_buffer);
//         break :encoder try Encoder.fromSlice(allocator, &reader.interface);
//     } else try Encoder.init(allocator);
//     defer encoder.deinit(allocator);

//     const output_buffer = try allocator.alloc(u8, Encoder.outputBufferBound(block_size));
//     defer allocator.free(output_buffer);

//     while (try source.nextBlock()) |block| {
//         const output_length = encoder.compressBlockToBuffer(block, output_buffer);
//         try writer.writeAll(output_buffer[0..output_length]);
//     }
//     try writer.flush();

//     if (config.export_stream) |export_stream| {
//         var export_writer = export_stream.writer(io, write_buffer);
//         try encoder.toSlice(&export_writer.interface);
//         try export_writer.interface.flush();
//     }
// }

// /// Decompresses blocks from `source` to `writer`, exporting the dictionary when `export_stream` is set.
// fn decode(
//     comptime Decoder: type,
//     allocator: std.mem.Allocator,
//     io: std.Io,
//     config: *const Config,
//     source: *Source,
//     writer: *std.Io.Writer,
//     write_buffer: []u8,
// ) !void {
//     var decoder = if (config.import_stream) |import_stream| decoder: {
//         var reader = import_stream.reader(io, &.{});
//         break :decoder try Decoder.fromSlice(allocator, &reader.interface);
//     } else try Decoder.init(allocator);
//     defer decoder.deinit(allocator);

//     const output_buffer = try allocator.alloc(u8, block_size);
//     defer allocator.free(output_buffer);

//     if (source.whole()) |data| {
//         var offset: usize = 0;
//         while (offset < data.len) {
//             const output_len = Decoder.exactOutputLength(data[offset..]);
//             if (output_len > block_size) return error.InvalidBlockLength;
//             offset += decoder.decompressBlockToBuffer(data[offset..], output_buffer[0..output_len]);
//             try writer.writeAll(output_buffer[0..output_len]);
//         }
//     } else {
//         const input_buffer = try allocator.alloc(u8, Decoder.outputBufferBound(block_size));
//         defer allocator.free(input_buffer);

//         var reader = if (source.mapped) |_| blk: {
//             var fixed = std.Io.Reader.fixed(source.mapped.?);
//             break :blk fixed;
//         } else source.reader.interface;

//         while (true) {
//             const block = reader.peek(input_buffer.len) catch |err| switch (err) {
//                 error.EndOfStream => reader.buffered(),
//                 else => |e| return e,
//             };
//             if (block.len == 0) break;

//             const output_len = Decoder.exactOutputLength(block);
//             if (output_len > block_size) return error.InvalidBlockLength;

//             const consumed = decoder.decompressBlockToBuffer(block, output_buffer[0..output_len]);
//             reader.toss(consumed);
//             try writer.writeAll(output_buffer[0..output_len]);
//         }
//     }
//     try writer.flush();

//     if (config.export_stream) |export_stream| {
//         var export_writer = export_stream.writer(io, write_buffer);
//         try decoder.toSlice(&export_writer.interface);
//         try export_writer.interface.flush();
//     }
// }

// /// Entry point: encodes or decodes a stream with the algorithm selected on the command line.
// pub fn main(init: std.process.Init) !void {
//     const allocator = init.arena.allocator();
//     const io = init.io;
//     var config = try Config.initFromArgs(allocator, io, init.minimal.args);
//     defer config.deinit(allocator, io);

//     var source = try Source.init(allocator, io, config.input_stream);
//     defer source.deinit(allocator);

//     const write_buffer = try allocator.alloc(u8, block_size);
//     defer allocator.free(write_buffer);
//     var output_writer = config.output_stream.writer(io, write_buffer);

//     switch (config.mode) {
//         inline else => |mode| switch (config.algorithm) {
//             inline else => |alg| {
//                 const Codec = switch (alg) {
//                     .white => firetrail.white,
//                     .orange => firetrail.orange,
//                     .red => firetrail.red,
//                 };
//                 switch (mode) {
//                     .encode => try encode(Codec.Encoder, allocator, io, &config, &source, &output_writer.interface, write_buffer),
//                     .decode => try decode(Codec.Decoder, allocator, io, &config, &source, &output_writer.interface, write_buffer),
//                 }
//             },
//         },
//     }
// }
