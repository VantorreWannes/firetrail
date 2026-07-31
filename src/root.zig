const std = @import("std");
const luts = @import("luts.zig");
const hashers = @import("hashers.zig");
/// White algorithm: static-dictionary dictionary coder.
pub const white = @import("algorithms/white.zig");
/// Orange algorithm: adaptive dictionary coder.
pub const orange = @import("algorithms/orange.zig");
/// Red algorithm: adaptive dictionary coder with frequency-tracked dictionary.
pub const red = @import("algorithms/red.zig");

test {
    std.testing.refAllDecls(luts);
    std.testing.refAllDecls(hashers);
    std.testing.refAllDecls(white);
    std.testing.refAllDecls(orange);
    std.testing.refAllDecls(red);
}
