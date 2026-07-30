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
            self.ctx.reset();
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
            self.ctx.reset();
        }
    };
}

pub fn TableExportBenchmark(Encoder: type) type {
    return struct {
        const Self = @This();
        encoder: *Encoder,
        input: []const u8,
        output: []u8,

        pub fn init(encoder: *Encoder, input: []const u8, output: []u8) Self {
            return .{ .encoder = encoder, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            _ = self.encoder.compressBlockToBuffer(self.input, self.output);
            _ = self.encoder.exportTable() catch {};
        }
    };
}

pub fn TableImportBenchmark(Decoder: type) type {
    return struct {
        const Self = @This();
        decoder: *Decoder,
        table_bytes: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, decoder: *Decoder, table_bytes: []const u8) !Self {
            return .{
                .decoder = decoder,
                .table_bytes = table_bytes,
                .allocator = allocator,
            };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            const table = Decoder.Table.initWithBuffer(self.allocator, self.table_bytes) catch unreachable;
            self.decoder.deinit(self.allocator);
            self.decoder.* = Decoder.initWithTable(table) catch unreachable;
        }
    };
}

pub fn WarmEncoderBenchmark(Encoder: type) type {
    return struct {
        const Self = @This();
        encoder: *Encoder,
        input: []const u8,
        output: []u8,

        pub fn init(encoder: *Encoder, input: []const u8, output: []u8) Self {
            return .{ .encoder = encoder, .input = input, .output = output };
        }

        pub fn run(self: *Self, _: std.mem.Allocator) void {
            _ = self.encoder.compressBlockToBuffer(self.input, self.output);
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

            const encoder_name = try std.fmt.allocPrint(arena, "White Encoder (cold): {s}", .{std.fs.path.basename(file_path)});
            const encoder_param = try arena.create(EncoderBenchmark(Encoder));
            encoder_param.* = EncoderBenchmark(Encoder).init(encoder, input_data, output_data);
            try bench.addParam(encoder_name, @as(*const EncoderBenchmark(Encoder), encoder_param), .{});

            const export_name = try std.fmt.allocPrint(arena, "White Export: {s}", .{std.fs.path.basename(file_path)});
            const export_param = try arena.create(TableExportBenchmark(Encoder));
            export_param.* = TableExportBenchmark(Encoder).init(encoder, input_data, output_data);
            try bench.addParam(export_name, @as(*const TableExportBenchmark(Encoder), export_param), .{});

            const table_bytes = try encoder.exportTable();

            const Decoder = firetrail.white.Decoder;
            const decoder = try arena.create(Decoder);
            decoder.* = try Decoder.init(arena);

            const import_name = try std.fmt.allocPrint(arena, "White Import: {s}", .{std.fs.path.basename(file_path)});
            const import_param = try arena.create(TableImportBenchmark(Decoder));
            import_param.* = try TableImportBenchmark(Decoder).init(arena, decoder, table_bytes);
            try bench.addParam(import_name, @as(*const TableImportBenchmark(Decoder), import_param), .{});

            const warm_name = try std.fmt.allocPrint(arena, "White Warm Encoder: {s}", .{std.fs.path.basename(file_path)});
            const warm_param = try arena.create(WarmEncoderBenchmark(Encoder));
            warm_param.* = WarmEncoderBenchmark(Encoder).init(encoder, input_data, output_data);
            try bench.addParam(warm_name, @as(*const WarmEncoderBenchmark(Encoder), warm_param), .{});

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
