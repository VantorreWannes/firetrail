const std = @import("std");
const firetrail = @import("root.zig");

const Mode = enum {
    decode,
    encode,
};

const Algorithm = enum {
    white,
    orange,
};

const Config = struct {
    algorithm: Algorithm,
    mode: Mode,
    input_stream: std.Io.File,
    output_stream: std.Io.File,
    import_stream: ?std.Io.File,
    export_stream: ?std.Io.File,

    pub fn initFromArgs(allocator: std.mem.Allocator, io: std.Io, args: std.process.Args) !Config {
        const args_slice = try args.toSlice(allocator);
        errdefer allocator.free(args_slice);

        if (args_slice.len < 5) {
            std.debug.print("Usage: {s} {{white|orange}} {{encode|decode}} <input> <output> [--import <lut_file>] [--export <lut_file>]\n", .{args_slice[0]});
            return error.MissingArguments;
        }

        const algorithm = if (std.mem.eql(u8, args_slice[1], "white"))
            Algorithm.white
        else if (std.mem.eql(u8, args_slice[1], "orange"))
            Algorithm.orange
        else {
            std.debug.print("Invalid algorithm: {s}\n", .{args_slice[1]});
            return error.InvalidAlgorithm;
        };

        const mode = if (std.mem.eql(u8, args_slice[2], "--encode") or std.mem.eql(u8, args_slice[2], "-e"))
            Mode.encode
        else if (std.mem.eql(u8, args_slice[2], "--decode") or std.mem.eql(u8, args_slice[2], "-d"))
            Mode.decode
        else {
            std.debug.print("Invalid mode: {s}\n", .{args_slice[2]});
            return error.InvalidMode;
        };

        const input_path = args_slice[3];
        const output_path = args_slice[4];

        if (std.mem.eql(u8, input_path, output_path)) {
            std.debug.print("Input and output paths must differ\n", .{});
            return error.InputEqualsOutput;
        }

        const cwd = std.Io.Dir.cwd();

        const input_stream = if (std.mem.eql(u8, input_path, "-")) std.Io.File.stdin() else try cwd.openFile(io, input_path, .{});
        const output_stream = if (std.mem.eql(u8, output_path, "-")) std.Io.File.stdout() else try cwd.createFile(io, output_path, .{});

        var import_stream: ?std.Io.File = null;
        var export_stream: ?std.Io.File = null;

        var i: usize = 5;
        while (i < args_slice.len) {
            if (std.mem.eql(u8, args_slice[i], "--import") and i + 1 < args_slice.len) {
                const path = args_slice[i + 1];
                import_stream = if (std.mem.eql(u8, path, "-")) std.Io.File.stdin() else try cwd.openFile(io, path, .{});
                i += 2;
            } else if (std.mem.eql(u8, args_slice[i], "--export") and i + 1 < args_slice.len) {
                const path = args_slice[i + 1];
                export_stream = if (std.mem.eql(u8, path, "-")) std.Io.File.stdout() else try cwd.createFile(io, path, .{});
                i += 2;
            } else {
                std.debug.print("Unknown argument: {s}\n", .{args_slice[i]});
                return error.InvalidArguments;
            }
        }

        return Config{
            .algorithm = algorithm,
            .mode = mode,
            .input_stream = input_stream,
            .output_stream = output_stream,
            .import_stream = import_stream,
            .export_stream = export_stream,
        };
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator, io: std.Io) void {
        _ = allocator;
        self.input_stream.close(io);
        self.output_stream.close(io);
        if (self.import_stream) |stream| stream.close(io);
        if (self.export_stream) |stream| stream.close(io);
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    var config = try Config.initFromArgs(arena, io, init.minimal.args);
    defer config.deinit(arena, io);

    switch (config.mode) {
        .encode => {
            switch (config.algorithm) {
                inline else => |alg| {
                    const Encoder = switch (alg) {
                        .white => firetrail.white.Encoder,
                        .orange => firetrail.orange.Encoder,
                    };

                    var encoder = try Encoder.init(arena);

                    if (config.import_stream) |import_stream| {
                        var import_buffer: [1024 * 4]u8 = undefined;
                        var import_reader = import_stream.reader(io, &import_buffer);
                        const import_slice = try import_reader.interface.allocRemaining(arena, .unlimited);
                        defer arena.free(import_slice);

                        const table = try Encoder.Table.initWithBuffer(arena, import_slice);
                        encoder.deinit(arena);
                        encoder = try Encoder.initWithTable(table);
                    }

                    defer encoder.deinit(arena);

                    var input_buffer: [1024 * 4]u8 = undefined;
                    var input_reader = config.input_stream.reader(io, &input_buffer);
                    const input_slice = try input_reader.interface.allocRemaining(arena, .unlimited);

                    const output_buffer_size = Encoder.outputBufferBound(input_slice.len);
                    const output_buffer = try arena.alloc(u8, output_buffer_size);

                    const output_bytes_written = encoder.compressBlockToBuffer(input_slice, output_buffer);
                    try config.output_stream.writeStreamingAll(io, output_buffer[0..output_bytes_written]);

                    if (config.export_stream) |export_stream| {
                        const export_buffer = try encoder.exportTable(arena);
                        try export_stream.writeStreamingAll(io, export_buffer);
                    }
                },
            }
        },
        .decode => {
            switch (config.algorithm) {
                inline else => |alg| {
                    const Decoder = switch (alg) {
                        .white => firetrail.white.Decoder,
                        .orange => firetrail.orange.Decoder,
                    };

                    var decoder = try Decoder.init(arena);

                    if (config.import_stream) |import_stream| {
                        var import_buffer: [1024 * 4]u8 = undefined;
                        var import_reader = import_stream.reader(io, &import_buffer);
                        const import_slice = try import_reader.interface.allocRemaining(arena, .unlimited);
                        defer arena.free(import_slice);

                        const table = try Decoder.Table.initWithBuffer(arena, import_slice);
                        decoder.deinit(arena);
                        decoder = try Decoder.initWithTable(table);
                    }

                    defer decoder.deinit(arena);

                    var input_buffer: [1024 * 4]u8 = undefined;
                    var input_reader = config.input_stream.reader(io, &input_buffer);
                    const input_slice = try input_reader.interface.allocRemaining(arena, .unlimited);

                    const uncompressed_size = Decoder.exactOutputLength(input_slice);
                    const output_buffer = try arena.alloc(u8, uncompressed_size);

                    _ = decoder.decompressBlockToBuffer(input_slice, output_buffer);
                    try config.output_stream.writeStreamingAll(io, output_buffer);
                },
            }
        },
    }
}
