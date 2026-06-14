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

    const program_arg_missing = program_arg == null;
    const algorithm_arg_missing = algorithm_arg == null;
    const mode_arg_missing = mode_arg == null;
    const input_arg_missing = input_arg == null;
    const output_arg_missing = output_arg == null;

    if (program_arg_missing or algorithm_arg_missing or mode_arg_missing or input_arg_missing or output_arg_missing) {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_arg orelse "firetrail"});
        return error.MissingArguments;
    }

    const program_value = program_arg orelse "firetrail";
    const algorithm_value = algorithm_arg orelse unreachable;
    const mode_value = mode_arg orelse unreachable;
    const input_value = input_arg orelse unreachable;
    const output_value = output_arg orelse unreachable;

    const input_arg_equals_output_arg = std.mem.eql(u8, input_value, output_value);

    if (input_arg_equals_output_arg) {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_value});
        return error.InputEqualsOutput;
    }

    const algorithm_option = if (std.mem.eql(u8, algorithm_value, "orange")) Algorithm.orange else if (std.mem.eql(u8, algorithm_value, "white")) Algorithm.white else null;

    const invalid_algorithm = algorithm_option == null;

    if (invalid_algorithm) {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_value});
        return error.InvalidAlgorithm;
    }

    const algorithm = algorithm_option orelse unreachable;

    const mode_option = if (std.mem.eql(u8, mode_value, "--encode") or std.mem.eql(u8, mode_value, "-e")) Mode.encode else if (std.mem.eql(u8, mode_value, "--decode") or std.mem.eql(u8, mode_value, "-d")) Mode.decode else null;

    const invalid_mode = mode_option == null;

    if (invalid_mode) {
        std.debug.print("Usage: {s} [orange | white] [--encode | --decode] <input> <output>\n", .{program_value});
        return error.InvalidMode;
    }

    const mode = mode_option orelse unreachable;

    const cwd = std.Io.Dir.cwd();

    const input_is_cli = std.mem.eql(u8, input_value, "-");
    const output_is_cli = std.mem.eql(u8, output_value, "-");

    const input_file = if (input_is_cli) std.Io.File.stdin() else try cwd.openFile(io, input_value, .{});
    defer input_file.close(io);
    var input_file_index: usize = 0;

    const output_file = if (output_is_cli) std.Io.File.stdout() else try cwd.createFile(io, output_value, .{});
    defer output_file.close(io);
    var output_file_index: usize = 0;

    switch (mode) {
        Mode.encode => {
            switch (algorithm) {
                inline else => |alg| {
                    const Encoder = switch (alg) {
                        .orange => firetrail.orange.Encoder,
                        .white => firetrail.white.Encoder,
                    };

                    var encoder = try Encoder.init(arena);
                    defer encoder.deinit(arena);

                    const input_buffer_size = 1024 * 1024 * 128;
                    const output_buffer_size = Encoder.outputBufferBound(input_buffer_size);

                    const input_buffer = try arena.alloc(u8, input_buffer_size);
                    const output_buffer = try arena.alloc(u8, output_buffer_size);

                    const input_reader_buffer_size = 1024 * 1024 * 128;
                    const output_writer_buffer_size = 1024 * 1024 * 128;

                    const input_reader_buffer = try arena.alloc(u8, input_reader_buffer_size);
                    var input_reader = input_file.reader(io, input_reader_buffer);

                    const output_writer_buffer = try arena.alloc(u8, output_writer_buffer_size);
                    var output_writer = output_file.writer(io, output_writer_buffer);

                    var input_bytes_read = try input_reader.interface.readSliceShort(input_buffer);
                    input_file_index += input_bytes_read;
                    while (input_bytes_read > 0) {
                        const output_bytes_written = encoder.compressBlockToBuffer(input_buffer[0..input_bytes_read], output_buffer);
                        try output_writer.interface.writeAll(output_buffer[0..output_bytes_written]);
                        output_file_index += output_bytes_written;

                        input_bytes_read = try input_reader.interface.readSliceShort(input_buffer);
                        input_file_index += input_bytes_read;
                    }

                    try output_writer.interface.flush();
                },
            }
        },
        Mode.decode => {
            switch (algorithm) {
                inline else => |alg| {
                    const Decoder = switch (alg) {
                        .orange => firetrail.orange.Decoder,
                        .white => firetrail.white.Decoder,
                    };
                    const Encoder = switch (alg) {
                        .orange => firetrail.orange.Encoder,
                        .white => firetrail.white.Encoder,
                    };

                    var decoder = try Decoder.init(arena);
                    defer decoder.deinit(arena);

                    const output_buffer_size = 1024 * 1024 * 128;
                    const input_buffer_size = Encoder.outputBufferBound(output_buffer_size);

                    const input_buffer = try arena.alloc(u8, input_buffer_size);
                    const output_buffer = try arena.alloc(u8, output_buffer_size);

                    const input_reader_buffer_size = 1024 * 1024 * 128;
                    const output_writer_buffer_size = 1024 * 1024 * 128;

                    const input_reader_buffer = try arena.alloc(u8, input_reader_buffer_size);
                    var input_reader = input_file.reader(io, input_reader_buffer);

                    const output_writer_buffer = try arena.alloc(u8, output_writer_buffer_size);
                    var output_writer = output_file.writer(io, output_writer_buffer);

                    var input_bytes_read = try input_reader.interface.readSliceShort(input_buffer);
                    input_file_index += input_bytes_read;
                    while (input_bytes_read > 0) {
                        const output_bytes_written = Decoder.exactOutputLength(input_buffer[0..input_bytes_read]);
                        _ = decoder.decompressBlockToBuffer(input_buffer[0..input_bytes_read], output_buffer[0..output_bytes_written]);
                        try output_writer.interface.writeAll(output_buffer[0..output_bytes_written]);
                        output_file_index += output_bytes_written;

                        input_bytes_read = try input_reader.interface.readSliceShort(input_buffer);
                        input_file_index += input_bytes_read;
                    }

                    try output_writer.interface.flush();
                },
            }
        },
    }
}
