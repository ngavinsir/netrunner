const std = @import("std");
const state = @import("state.zig");

const splitmix_gamma: u64 = 0x9E3779B97F4A7C15;
const splitmix_mul_1: u64 = 0xBF58476D1CE4E5B9;
const splitmix_mul_2: u64 = 0x94D049BB133111EB;

pub const RngState = u64;

pub fn init(seed: state.Seed) RngState {
    return seed;
}

pub fn oracleSeed(rng_state: RngState) state.RngSeed {
    return @bitCast(rng_state);
}

pub fn fromOracleSeed(seed: state.RngSeed) RngState {
    return @bitCast(seed);
}

pub fn randBelow(rng_state: *RngState, upper_bound: usize) usize {
    std.debug.assert(upper_bound > 0);
    const next = nextWord(rng_state.*);
    rng_state.* = next.seed;
    return @intCast(next.word % upper_bound);
}

pub fn shuffleInPlace(comptime T: type, rng_state: *RngState, items: []T) void {
    if (items.len <= 1) return;
    var i = items.len - 1;
    while (i > 0) : (i -= 1) {
        const j = randBelow(rng_state, i + 1);
        std.mem.swap(T, &items[i], &items[j]);
    }
}

fn nextWord(seed: RngState) struct { seed: RngState, word: u64 } {
    const next_seed = seed +% splitmix_gamma;
    const z1 = (next_seed ^ (next_seed >> 30)) *% splitmix_mul_1;
    const z2 = (z1 ^ (z1 >> 27)) *% splitmix_mul_2;
    return .{
        .seed = next_seed,
        .word = z2 ^ (z2 >> 31),
    };
}
