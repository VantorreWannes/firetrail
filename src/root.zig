const std = @import("std");
const luts = @import("luts.zig");

test {
    std.testing.refAllDecls(luts);
}
