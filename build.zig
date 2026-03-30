const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parity_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_parity_tests = b.addRunArtifact(parity_tests);

    const test_step = b.step("test", "Run Zig parity fixture tests");
    test_step.dependOn(&run_parity_tests.step);

    // Compile-only step (no run) for quick error checking
    const check_step = b.step("check", "Compile tests without running");
    check_step.dependOn(&parity_tests.step);

    b.default_step.dependOn(test_step);
}
