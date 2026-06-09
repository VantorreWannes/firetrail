const std = @import("std");
const luts = @import("luts.zig");
const hashers = @import("hashers.zig");
const white = @import("algorithms/white.zig");

test {
    std.testing.refAllDecls(luts);
    std.testing.refAllDecls(hashers);
    std.testing.refAllDecls(white);
}
