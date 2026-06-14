const std = @import("std");
const firetrail = @import("firetrail");

const Mode = enum {
    decode,
    encode,
};

const Algorithm = enum {
    orange,
    white,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    const program_arg = if (args.len > 0) args[0] else null;
    const algorithm_arg = if (args.len > 1) args[1] else null;
    const mode_arg = if (args.len > 2) args[2] else null;
    const input_arg = if (args.len > 3) args[3] else null;
    const output_arg = if (args.len > 4) args[4] else null;

    if (program_arg == null or algorithm_arg == null or mode_arg == null or input_arg == null or output_arg == null) {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_arg orelse "firetrail"});
        return error.MissingArguments;
    }

    const program_value = program_arg orelse "firetrail";
    const algorithm_value = algorithm_arg.?;
    const mode_value = mode_arg.?;
    const input_value = input_arg.?;
    const output_value = output_arg.?;

    if (std.mem.eql(u8, input_value, output_value)) {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_value});
        return error.InputEqualsOutput;
    }

    const algorithm = if (std.mem.eql(u8, algorithm_value, "orange"))
        Algorithm.orange
    else if (std.mem.eql(u8, algorithm_value, "white"))
        Algorithm.white
    else {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_value});
        return error.InvalidAlgorithm;
    };

    const mode = if (std.mem.eql(u8, mode_value, "--encode") or std.mem.eql(u8, mode_value, "-e"))
        Mode.encode
    else if (std.mem.eql(u8, mode_value, "--decode") or std.mem.eql(u8, mode_value, "-d"))
        Mode.decode
    else {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_value});
        return error.InvalidMode;
    };

    const cwd = std.Io.Dir.cwd();

    const input_is_cli = std.mem.eql(u8, input_value, "-");
    const output_is_cli = std.mem.eql(u8, output_value, "-");

    const input_file = if (input_is_cli) std.Io.File.stdin() else try cwd.openFile(io, input_value, .{});
    defer input_file.close(io);

    const output_file = if (output_is_cli) std.Io.File.stdout() else try cwd.createFile(io, output_value, .{});
    defer output_file.close(io);

    var read_buf: [4096]u8 = undefined;
    var input_reader = input_file.reader(io, &read_buf);
    const input_bytes = try input_reader.interface.allocRemaining(arena, .unlimited);

    switch (mode) {
        .encode => {
            switch (algorithm) {
                inline else => |alg| {
                    const Encoder = switch (alg) {
                        .orange => firetrail.orange.Encoder,
                        .white => firetrail.white.Encoder,
                    };

                    var encoder = try Encoder.init(arena);
                    defer encoder.deinit(arena);

                    const output_buffer_size = Encoder.outputBufferBound(input_bytes.len);
                    const output_buffer = try arena.alloc(u8, output_buffer_size);

                    const output_bytes_written = encoder.compressBlockToBuffer(input_bytes, output_buffer);
                    try output_file.writeStreamingAll(io, output_buffer[0..output_bytes_written]);
                },
            }
        },
        .decode => {
            switch (algorithm) {
                inline else => |alg| {
                    const Decoder = switch (alg) {
                        .orange => firetrail.orange.Decoder,
                        .white => firetrail.white.Decoder,
                    };

                    var decoder = try Decoder.init(arena);
                    defer decoder.deinit(arena);

                    const uncompressed_size = Decoder.exactOutputLength(input_bytes);
                    const output_buffer = try arena.alloc(u8, uncompressed_size);

                    _ = decoder.decompressBlockToBuffer(input_bytes, output_buffer);
                    try output_file.writeStreamingAll(io, output_buffer);
                },
            }
        },
    }
}
