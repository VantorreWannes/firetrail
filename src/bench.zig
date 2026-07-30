const std = @import("std");
const Io = std.Io;
const zbench = @import("zbench");
const firetrail = @import("firetrail");

fn readFile(allocator: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);

    var reader = file.readerStreaming(io, &.{});

    return try reader.interface.allocRemaining(allocator, .unlimited);
}

pub fn EncoderBenchmark(Encoder: type) type {
    return struct {
        const Self = @This();
        ctx: *Encoder,
        input: []const u8,
        output: []u8,

        pub fn init(ctx: *Encoder, input: []const u8, output: []u8) Self {
            return .{ .ctx = ctx, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            _ = self.ctx.compressBlockToBuffer(self.input, self.output);
        }
    };
}

pub fn DecoderBenchmark(Decoder: type) type {
    return struct {
        const Self = @This();
        ctx: *Decoder,
        input: []const u8,
        output: []u8,

        pub fn init(ctx: *Decoder, input: []const u8, output: []u8) Self {
            return .{ .ctx = ctx, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            _ = self.ctx.decompressBlockToBuffer(self.input, self.output);
        }
    };
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    var bench = zbench.Benchmark.init(arena, .{});
    defer bench.deinit();

    if (args.len > 1) {
        const file_path = args[1];
        try writer.print("Loading {s}...\n", .{file_path});
        try writer.flush();

        const input_data = try readFile(arena, io, file_path);

        {
            const Encoder = firetrail.white.Encoder;
            const encoder = try arena.create(Encoder);
            encoder.* = try Encoder.init(arena);

            const output_data = try arena.alloc(u8, Encoder.outputBufferBound(input_data.len));
            const encoder_name = try std.fmt.allocPrint(arena, "White Encoder: {s}", .{std.fs.path.basename(file_path)});
            const encoder_param = try arena.create(EncoderBenchmark(Encoder));
            encoder_param.* = EncoderBenchmark(Encoder).init(encoder, input_data, output_data);
            try bench.addParam(encoder_name, @as(*const EncoderBenchmark(Encoder), encoder_param), .{});

            const Decoder = firetrail.white.Decoder;
            const decoder = try arena.create(Decoder);
            decoder.* = try Decoder.init(arena);

            const compressed_buffer = try arena.alloc(u8, Encoder.outputBufferBound(input_data.len));
            const compressed_size = encoder.compressBlockToBuffer(input_data, compressed_buffer);
            const compressed_data = compressed_buffer[0..compressed_size];

            const decompressed_data = try arena.alloc(u8, input_data.len);
            const decoder_name = try std.fmt.allocPrint(arena, "White Decoder: {s}", .{std.fs.path.basename(file_path)});

            const decode_param = try arena.create(DecoderBenchmark(Decoder));
            decode_param.* = DecoderBenchmark(Decoder).init(decoder, compressed_data, decompressed_data);

            try bench.addParam(decoder_name, @as(*const DecoderBenchmark(Decoder), decode_param), .{});
        }
    }

    try writer.writeAll("\n");
    try writer.flush();
    try bench.run(io, std.Io.File.stdout());
}
