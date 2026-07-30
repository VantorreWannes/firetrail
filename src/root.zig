const std = @import("std");
const luts = @import("luts.zig");
const hashers = @import("hashers.zig");
pub const white = @import("algorithms/white.zig");
pub const orange = @import("algorithms/orange.zig");

test {
    std.testing.refAllDecls(luts);
    std.testing.refAllDecls(hashers);
    std.testing.refAllDecls(white);
    std.testing.refAllDecls(orange);
}
