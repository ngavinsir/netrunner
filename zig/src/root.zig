const std = @import("std");

pub const engine = struct {
    pub const flow = @import("engine/flow.zig");
    pub const generator = @import("engine/generator.zig");
    pub const matchups = @import("engine/matchups.zig");
    pub const parity = @import("engine/parity.zig");
    pub const rng = @import("engine/rng.zig");
    pub const state = @import("engine/state.zig");
    pub const setup = @import("engine/setup.zig");
};
pub const fixture = @import("parity/fixture.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
