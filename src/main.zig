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
            std.debug.print("Usage: {s} {{white|orange}} {{--encode|-e|--decode|-d}} <input> <output> [--import <lut_file>] [--export <lut_file>]\n", .{args_slice[0]});
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

const block_size = 1024 * 4;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    var config = try Config.initFromArgs(allocator, io, init.minimal.args);
    defer config.deinit(allocator, io);

    var read_buffer: [block_size]u8 = undefined;
    var write_buffer: [block_size]u8 = undefined;

    switch (config.mode) {
        .encode => {
            switch (config.algorithm) {
                inline else => |alg| {
                    const Encoder = switch (alg) {
                        .white => firetrail.white.Encoder,
                        .orange => firetrail.orange.Encoder,
                    };

                    var encoder = if (config.import_stream) |import_stream| encoder: {
                        var reader = import_stream.reader(io, &read_buffer);
                        break :encoder try Encoder.fromReader(allocator, &reader.interface);
                    } else try Encoder.init(allocator);

                    defer encoder.deinit(allocator);

                    var input_buffer: [block_size]u8 = undefined;
                    var output_buffer: [Encoder.outputBufferBound(block_size)]u8 = undefined;

                    var input_reader = config.input_stream.reader(io, &read_buffer);
                    var output_writer = config.output_stream.writer(io, &write_buffer);

                    var input_length = try input_reader.interface.readSliceShort(&input_buffer);

                    while (input_length > 0) {
                        const output_length = encoder.compressBlockToBuffer(input_buffer[0..input_length], &output_buffer);
                        try output_writer.interface.writeAll(output_buffer[0..output_length]);
                        input_length = try input_reader.interface.readSliceShort(&input_buffer);
                    }

                    try output_writer.interface.flush();

                    if (config.export_stream) |export_stream| {
                        var writer = export_stream.writer(io, &write_buffer);
                        try encoder.toWriter(&writer.interface);
                        try writer.interface.flush();
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

                    var decoder = if (config.import_stream) |import_stream| decoder: {
                        var reader = import_stream.reader(io, &read_buffer);
                        break :decoder try Decoder.fromReader(allocator, &reader.interface);
                    } else try Decoder.init(allocator);

                    defer decoder.deinit(allocator);

                    var input_reader = config.input_stream.reader(io, &read_buffer);
                    const compressed = try input_reader.interface.allocRemaining(allocator, .unlimited);

                    var output_writer = config.output_stream.writer(io, &write_buffer);

                    var offset: usize = 0;
                    while (offset < compressed.len) {
                        const block = compressed[offset..];
                        const output_len = Decoder.exactOutputLength(block);
                        const output_buffer = try allocator.alloc(u8, output_len);

                        const consumed = decoder.decompressBlockToBuffer(block, output_buffer);
                        if (consumed == 0) return error.TruncatedInput;

                        try output_writer.interface.writeAll(output_buffer);
                        offset += consumed;
                    }

                    try output_writer.interface.flush();

                    if (config.export_stream) |export_stream| {
                        var writer = export_stream.writer(io, &write_buffer);
                        try decoder.toWriter(&writer.interface);
                        try writer.interface.flush();
                    }
                },
            }
        },
    }
}
