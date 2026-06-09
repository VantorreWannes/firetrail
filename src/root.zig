const std = @import("std");
const luts = @import("luts.zig");
const hashers = @import("hashers.zig");

test {
    std.testing.refAllDecls(luts);
    std.testing.refAllDecls(hashers);
}
