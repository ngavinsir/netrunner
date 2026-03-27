const std = @import("std");

pub const engine = struct {
    pub const catalog = @import("engine/game.zig");
    pub const game = @import("engine/game.zig");
    pub const parity = @import("engine/parity.zig");
    pub const state = @import("engine/state.zig");
};
pub const oracle = @import("parity/oracle.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
