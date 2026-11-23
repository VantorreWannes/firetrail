const std = @import("std");
const firetrail = @import("root.zig");

const allocator = std.heap.c_allocator;
const table_byte_size = (std.math.maxInt(u16) + 1) * @sizeOf(u64);

const Algorithm = enum(c_int) {
    white = -1,
    orange = 0,
    red = 1,
};

const Encoder = union(Algorithm) {
    white: firetrail.white.Encoder,
    orange: firetrail.orange.Encoder,
    red: firetrail.red.Encoder,
};

const Decoder = union(Algorithm) {
    white: firetrail.white.Decoder,
    orange: firetrail.orange.Decoder,
    red: firetrail.red.Decoder,
};

export fn firetrail_max_compressed_size(input_size: usize) usize {
    return firetrail.orange.Encoder.outputBufferBound(input_size);
}

export fn firetrail_table_size() usize {
    return table_byte_size;
}

export fn firetrail_train_table(
    sample_ptr: ?[*]const u8,
    sample_size: usize,
    output_table_ptr: ?[*]u8,
    output_capacity: usize,
) usize {
    const sample = sample_ptr orelse return 0;
    const output_table = output_table_ptr orelse return 0;
    if (sample_size == 0 or output_capacity < table_byte_size) return 0;

    var encoder = firetrail.red.Encoder.init(allocator) catch return 0;
    defer encoder.deinit(allocator);

    const scratch = allocator.alloc(u8, firetrail.red.Encoder.outputBufferBound(sample_size)) catch return 0;
    defer allocator.free(scratch);

    _ = encoder.compressBlockToBuffer(sample[0..sample_size], scratch);
    @memcpy(output_table[0..table_byte_size], std.mem.sliceAsBytes(encoder.table.values));
    return table_byte_size;
}

export fn firetrail_encoder_create(raw_algorithm: c_int) ?*Encoder {
    const algorithm = std.enums.fromInt(Algorithm, raw_algorithm) orelse return null;
    const encoder = allocator.create(Encoder) catch return null;
    errdefer allocator.destroy(encoder);

    encoder.* = switch (algorithm) {
        .white => .{ .white = firetrail.white.Encoder.init(allocator) catch return null },
        .orange => .{ .orange = firetrail.orange.Encoder.init(allocator) catch return null },
        .red => .{ .red = firetrail.red.Encoder.init(allocator) catch return null },
    };
    return encoder;
}

export fn firetrail_encoder_destroy(maybe_encoder: ?*Encoder) void {
    const encoder = maybe_encoder orelse return;
    switch (encoder.*) {
        inline else => |*impl| impl.deinit(allocator),
    }
    allocator.destroy(encoder);
}

export fn firetrail_encoder_reset(maybe_encoder: ?*Encoder) void {
    const encoder = maybe_encoder orelse return;
    switch (encoder.*) {
        inline else => |*impl| impl.reset(),
    }
}

export fn firetrail_encoder_import_table(
    maybe_encoder: ?*Encoder,
    table_ptr: ?[*]const u8,
    table_size: usize,
) bool {
    const encoder = maybe_encoder orelse return false;
    const table = table_ptr orelse return false;
    if (table_size != table_byte_size) return false;

    const source = table[0..table_byte_size];
    switch (encoder.*) {
        .white => |*impl| @memcpy(std.mem.sliceAsBytes(impl.table.table), source),
        .orange => |*impl| @memcpy(std.mem.sliceAsBytes(impl.table.table), source),
        .red => |*impl| {
            @memcpy(std.mem.sliceAsBytes(impl.table.values), source);
            @memset(impl.table.counts, 0);
        },
    }
    return true;
}

export fn firetrail_encoder_export_table(
    maybe_encoder: ?*const Encoder,
    output_table_ptr: ?[*]u8,
    output_capacity: usize,
) usize {
    const encoder = maybe_encoder orelse return 0;
    const output_table = output_table_ptr orelse return 0;
    if (output_capacity < table_byte_size) return 0;

    const destination = output_table[0..table_byte_size];
    switch (encoder.*) {
        .white => |*impl| @memcpy(destination, std.mem.sliceAsBytes(impl.table.table)),
        .orange => |*impl| @memcpy(destination, std.mem.sliceAsBytes(impl.table.table)),
        .red => |*impl| @memcpy(destination, std.mem.sliceAsBytes(impl.table.values)),
    }
    return table_byte_size;
}

export fn firetrail_encoder_compress(
    maybe_encoder: ?*Encoder,
    input_ptr: ?[*]const u8,
    input_size: usize,
    output_ptr: ?[*]u8,
    output_capacity: usize,
) usize {
    const encoder = maybe_encoder orelse return 0;
    if (input_size == 0) return 0;
    const input = input_ptr orelse return 0;
    const output = output_ptr orelse return 0;
    if (output_capacity < firetrail_max_compressed_size(input_size)) return 0;

    return switch (encoder.*) {
        inline else => |*impl| impl.compressBlockToBuffer(input[0..input_size], output[0..output_capacity]),
    };
}

export fn firetrail_decoder_create(raw_algorithm: c_int) ?*Decoder {
    const algorithm = std.enums.fromInt(Algorithm, raw_algorithm) orelse return null;
    const decoder = allocator.create(Decoder) catch return null;
    errdefer allocator.destroy(decoder);

    decoder.* = switch (algorithm) {
        .white => .{ .white = firetrail.white.Decoder.init(allocator) catch return null },
        .orange => .{ .orange = firetrail.orange.Decoder.init(allocator) catch return null },
        .red => .{ .red = firetrail.red.Decoder.init(allocator) catch return null },
    };
    return decoder;
}

export fn firetrail_decoder_destroy(maybe_decoder: ?*Decoder) void {
    const decoder = maybe_decoder orelse return;
    switch (decoder.*) {
        inline else => |*impl| impl.deinit(allocator),
    }
    allocator.destroy(decoder);
}

export fn firetrail_decoder_reset(maybe_decoder: ?*Decoder) void {
    const decoder = maybe_decoder orelse return;
    switch (decoder.*) {
        inline else => |*impl| impl.reset(),
    }
}

export fn firetrail_decoder_import_table(
    maybe_decoder: ?*Decoder,
    table_ptr: ?[*]const u8,
    table_size: usize,
) bool {
    const decoder = maybe_decoder orelse return false;
    const table = table_ptr orelse return false;
    if (table_size != table_byte_size) return false;

    const source = table[0..table_byte_size];
    switch (decoder.*) {
        .white => |*impl| @memcpy(std.mem.sliceAsBytes(impl.table.table), source),
        .orange => |*impl| @memcpy(std.mem.sliceAsBytes(impl.table.table), source),
        .red => |*impl| {
            @memcpy(std.mem.sliceAsBytes(impl.table.values), source);
            @memset(impl.table.counts, 0);
        },
    }
    return true;
}

export fn firetrail_decoder_export_table(
    maybe_decoder: ?*const Decoder,
    output_table_ptr: ?[*]u8,
    output_capacity: usize,
) usize {
    const decoder = maybe_decoder orelse return 0;
    const output_table = output_table_ptr orelse return 0;
    if (output_capacity < table_byte_size) return 0;

    const destination = output_table[0..table_byte_size];
    switch (decoder.*) {
        .white => |*impl| @memcpy(destination, std.mem.sliceAsBytes(impl.table.table)),
        .orange => |*impl| @memcpy(destination, std.mem.sliceAsBytes(impl.table.table)),
        .red => |*impl| @memcpy(destination, std.mem.sliceAsBytes(impl.table.values)),
    }
    return table_byte_size;
}

export fn firetrail_decoder_decompress(
    maybe_decoder: ?*Decoder,
    input_ptr: ?[*]const u8,
    input_size: usize,
    output_ptr: ?[*]u8,
    output_size: usize,
) usize {
    const decoder = maybe_decoder orelse return 0;
    if (output_size == 0) return 0;
    const input = input_ptr orelse return 0;
    const output = output_ptr orelse return 0;

    _ = switch (decoder.*) {
        inline else => |*impl| impl.decompressBlockToBuffer(input[0..input_size], output[0..output_size]),
    };
    return output_size;
}
