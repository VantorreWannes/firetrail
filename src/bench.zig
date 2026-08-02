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

fn addEncoderBenchmarks(
    bench: *zbench.Benchmark,
    allocator: std.mem.Allocator,
    comptime label: []const u8,
    comptime Encoder: type,
    file_path: []const u8,
    input_data: []const u8,
    lut: []u8,
) !void {
    const basename = std.fs.path.basename(file_path);

    const output_buffer_bound = Encoder.outputBufferBound(input_data.len);
    const output_data_buffer = try allocator.alloc(u8, output_buffer_bound);
    defer allocator.free(output_data_buffer);

    const cold_encoder = try allocator.create(Encoder);
    cold_encoder.* = try Encoder.init(allocator);
    const cold_encoder_name = try std.fmt.allocPrint(allocator, label ++ "Encoder (cold): {s}", .{basename});
    const cold_encoder_param = try allocator.create(ColdEncoderBenchmark(Encoder));
    cold_encoder_param.* = ColdEncoderBenchmark(Encoder).init(cold_encoder, input_data, output_data_buffer);
    try bench.addParam(cold_encoder_name, @as(*const ColdEncoderBenchmark(Encoder), cold_encoder_param), .{});

    const warm_encoder = try allocator.create(Encoder);
    warm_encoder.* = try Encoder.fromSlice(allocator, lut);
    const warm_encoder_name = try std.fmt.allocPrint(allocator, label ++ "Encoder (warm): {s}", .{basename});
    const warm_encoder_param = try allocator.create(WarmEncoderBenchmark(Encoder));
    warm_encoder_param.* = WarmEncoderBenchmark(Encoder).init(warm_encoder, input_data, output_data_buffer);
    try bench.addParam(warm_encoder_name, @as(*const WarmEncoderBenchmark(Encoder), warm_encoder_param), .{});
}

fn addDecoderBenchmarks(
    bench: *zbench.Benchmark,
    allocator: std.mem.Allocator,
    comptime label: []const u8,
    comptime Decoder: type,
    file_path: []const u8,
    input_data: []const u8,
    output_data_length: usize,
    lut: []u8,
) !void {
    const basename = std.fs.path.basename(file_path);

    const output_buffer_bound = output_data_length;
    const output_data_buffer = try allocator.alloc(u8, output_buffer_bound);
    defer allocator.free(output_data_buffer);

    const cold_encoder = try allocator.create(Decoder);
    cold_encoder.* = try Decoder.init(allocator);
    const cold_decoder_name = try std.fmt.allocPrint(allocator, label ++ "Decoder (cold): {s}", .{basename});
    const cold_decoder_param = try allocator.create(ColdDecoderBenchmark(Decoder));
    cold_decoder_param.* = ColdDecoderBenchmark(Decoder).init(cold_encoder, input_data, output_data_buffer);
    try bench.addParam(cold_decoder_name, @as(*const ColdDecoderBenchmark(Decoder), cold_decoder_param), .{});

    const warm_encoder = try allocator.create(Decoder);
    warm_encoder.* = try Decoder.fromSlice(allocator, lut);
    const warm_decoder_name = try std.fmt.allocPrint(allocator, label ++ "Decoder (warm): {s}", .{basename});
    const warm_decoder_param = try allocator.create(WarmDecoderBenchmark(Decoder));
    warm_decoder_param.* = WarmDecoderBenchmark(Decoder).init(warm_encoder, input_data, output_data_buffer);
    try bench.addParam(warm_decoder_name, @as(*const WarmDecoderBenchmark(Decoder), warm_decoder_param), .{});
}

fn trainDictionary(comptime Encoder: type, allocator: std.mem.Allocator, input_data: []const u8) ![]u8 {
    var encoder = try Encoder.init(allocator);

    const buffer = try allocator.alloc(u8, Encoder.outputBufferBound(input_data.len));
    _ = encoder.compressBlockToBuffer(input_data, buffer);

    return try encoder.toSlice(allocator);
}

fn encode(
    allocator: std.mem.Allocator,
    comptime Encoder: type,
    input_data: []const u8,
    lut: []u8,
) ![]u8 {
    var encoder = try Encoder.fromSlice(allocator, lut);
    defer encoder.deinit(allocator);
    const buf = try allocator.alloc(u8, Encoder.outputBufferBound(input_data.len));
    defer allocator.free(buf);
    const n = encoder.compressBlockToBuffer(input_data, buf);
    return try allocator.dupe(u8, buf[0..n]);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    if (args.len > 1) {
        const file_path = args[1];
        try writer.print("Loading {s}...\n", .{file_path});
        try writer.flush();

        const input_data = try readFile(allocator, io, file_path);

        {
            const lut = try trainDictionary(firetrail.red.Encoder, allocator, input_data);
            try addEncoderBenchmarks(&bench, allocator, "White", firetrail.white.Encoder, file_path, input_data, lut);
            const encoded = try encode(allocator, firetrail.white.Encoder, input_data, lut);
            try addDecoderBenchmarks(&bench, allocator, "White", firetrail.white.Decoder, file_path, encoded, input_data.len, lut);
        }

        {
            const lut = try trainDictionary(firetrail.orange.Encoder, allocator, input_data);
            try addEncoderBenchmarks(&bench, allocator, "Orange", firetrail.orange.Encoder, file_path, input_data, lut);
            const encoded = try encode(allocator, firetrail.orange.Encoder, input_data, lut);
            try addDecoderBenchmarks(&bench, allocator, "Orange", firetrail.orange.Decoder, file_path, encoded, input_data.len, lut);
        }

        {
            const lut = try trainDictionary(firetrail.red.Encoder, allocator, input_data);
            try addEncoderBenchmarks(&bench, allocator, "Red", firetrail.red.Encoder, file_path, input_data, lut);
            const encoded = try encode(allocator, firetrail.red.Encoder, input_data, lut);
            try addDecoderBenchmarks(&bench, allocator, "Red", firetrail.red.Decoder, file_path, encoded, input_data.len, lut);
        }
    }

    try writer.writeAll("\n");
    try writer.flush();
    try bench.run(io, std.Io.File.stdout());
}
