const std = @import("std");
const Io = std.Io;
const zbench = @import("zbench");
const firetrail = @import("firetrail");

fn readFile(allocator: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    const cwd = std.Io.Dir.cwd();
    var file = try cwd.openFile(io, path, .{});
    defer file.close(io);

    var reader = file.readerStreaming(io, &.{});

    return try reader.interface.allocRemaining(allocator, .unlimited);
}

pub fn ColdEncoderBenchmark(Encoder: type) type {
    return struct {
        const Self = @This();
        ctx: *Encoder,
        input: []const u8,
        output: []u8,

        pub fn init(ctx: *Encoder, input: []const u8, output: []u8) Self {
            return .{ .ctx = ctx, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            self.ctx.reset();
            _ = self.ctx.compressBlockToBuffer(self.input, self.output);
        }
    };
}

pub fn ColdDecoderBenchmark(Decoder: type) type {
    return struct {
        const Self = @This();
        ctx: *Decoder,
        input: []const u8,
        output: []u8,

        pub fn init(ctx: *Decoder, input: []const u8, output: []u8) Self {
            return .{ .ctx = ctx, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            self.ctx.reset();
            _ = self.ctx.decompressBlockToBuffer(self.input, self.output);
        }
    };
}

pub fn WarmEncoderBenchmark(Encoder: type) type {
    return struct {
        const Self = @This();
        encoder: *Encoder,
        input: []const u8,
        output: []u8,

        pub fn init(decoder: *Encoder, input: []const u8, output: []u8) Self {
            return .{ .encoder = decoder, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            _ = self.encoder.compressBlockToBuffer(self.input, self.output);
        }
    };
}

pub fn WarmDecoderBenchmark(Decoder: type) type {
    return struct {
        const Self = @This();
        decoder: *Decoder,
        input: []const u8,
        output: []u8,

        pub fn init(decoder: *Decoder, input: []const u8, output: []u8) Self {
            return .{ .decoder = decoder, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            _ = self.decoder.decompressBlockToBuffer(self.input, self.output);
        }
    };
}

fn addBenchmarks(
    bench: *zbench.Benchmark,
    arena: std.mem.Allocator,
    comptime label: []const u8,
    comptime Encoder: type,
    comptime Decoder: type,
    file_path: []const u8,
    input_data: []const u8,
    dictionary: []const u8,
) !void {
    const basename = std.fs.path.basename(file_path);
    const buf = try arena.alloc(u8, Encoder.outputBufferBound(input_data.len));
    const decompressed_data = try arena.alloc(u8, input_data.len);

    const cold_encoder = try arena.create(Encoder);
    cold_encoder.* = try Encoder.init(arena);
    const cold_enc_name = try std.fmt.allocPrint(arena, label ++ " Encoder (cold): {s}", .{basename});
    const cold_enc_param = try arena.create(ColdEncoderBenchmark(Encoder));
    cold_enc_param.* = ColdEncoderBenchmark(Encoder).init(cold_encoder, input_data, buf);
    try bench.addParam(cold_enc_name, @as(*const ColdEncoderBenchmark(Encoder), cold_enc_param), .{});

    var dict_reader = std.Io.Reader.fixed(dictionary);
    const warm_encoder = try arena.create(Encoder);
    warm_encoder.* = try Encoder.fromReader(arena, &dict_reader);
    const compressed_size = warm_encoder.compressBlockToBuffer(input_data, buf);
    const compressed_data = try arena.dupe(u8, buf[0..compressed_size]);

    const warm_enc_name = try std.fmt.allocPrint(arena, label ++ " Encoder (warm): {s}", .{basename});
    const warm_enc_param = try arena.create(WarmEncoderBenchmark(Encoder));
    warm_enc_param.* = WarmEncoderBenchmark(Encoder).init(warm_encoder, input_data, buf);
    try bench.addParam(warm_enc_name, @as(*const WarmEncoderBenchmark(Encoder), warm_enc_param), .{});

    const cold_decoder = try arena.create(Decoder);
    cold_decoder.* = try Decoder.init(arena);
    const cold_dec_name = try std.fmt.allocPrint(arena, label ++ " Decoder (cold): {s}", .{basename});
    const cold_dec_param = try arena.create(ColdDecoderBenchmark(Decoder));
    cold_dec_param.* = ColdDecoderBenchmark(Decoder).init(cold_decoder, compressed_data, decompressed_data);
    try bench.addParam(cold_dec_name, @as(*const ColdDecoderBenchmark(Decoder), cold_dec_param), .{});

    var dict_reader2 = std.Io.Reader.fixed(dictionary);
    const warm_decoder = try arena.create(Decoder);
    warm_decoder.* = try Decoder.fromReader(arena, &dict_reader2);
    _ = warm_decoder.decompressBlockToBuffer(compressed_data, decompressed_data);

    const warm_dec_name = try std.fmt.allocPrint(arena, label ++ " Decoder (warm): {s}", .{basename});
    const warm_dec_param = try arena.create(WarmDecoderBenchmark(Decoder));
    warm_dec_param.* = WarmDecoderBenchmark(Decoder).init(warm_decoder, compressed_data, decompressed_data);
    try bench.addParam(warm_dec_name, @as(*const WarmDecoderBenchmark(Decoder), warm_dec_param), .{});
}

fn trainDictionary(arena: std.mem.Allocator, input_data: []const u8) ![]u8 {
    const Encoder = firetrail.red.Encoder;

    var encoder = try Encoder.init(arena);

    const buf = try arena.alloc(u8, Encoder.outputBufferBound(input_data.len));
    _ = encoder.compressBlockToBuffer(input_data, buf);

    var dict_writer = std.Io.Writer.Allocating.init(arena);
    try encoder.toWriter(&dict_writer.writer);
    return dict_writer.toOwnedSlice();
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

        try writer.print("Training dictionary...\n", .{});
        try writer.flush();
        const dictionary = try trainDictionary(arena, input_data);

        try addBenchmarks(&bench, arena, "White", firetrail.white.Encoder, firetrail.white.Decoder, file_path, input_data, dictionary);
        try addBenchmarks(&bench, arena, "Red", firetrail.red.Encoder, firetrail.red.Decoder, file_path, input_data, dictionary);
        try addBenchmarks(&bench, arena, "Orange", firetrail.orange.Encoder, firetrail.orange.Decoder, file_path, input_data, dictionary);
    }

    try writer.writeAll("\n");
    try writer.flush();
    try bench.run(io, std.Io.File.stdout());
}
