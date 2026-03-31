const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // libvaxis dependency
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    // Shared library (for C/C++/Python consumers like OpenSpiel)
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "netrunner",
        .linkage = .dynamic,
        .root_module = lib_module,
    });
    b.installArtifact(lib);

    // Static library
    const static_module = b.createModule(.{
        .root_source_file = b.path("src/api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const static_lib = b.addLibrary(.{
        .name = "netrunner_static",
        .linkage = .static,
        .root_module = static_module,
    });
    b.installArtifact(static_lib);

    // TUI executable (with libvaxis)
    const tui_module = b.createModule(.{
        .root_source_file = b.path("src/tui.zig"),
        .target = target,
        .optimize = optimize,
    });
    tui_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    const tui = b.addExecutable(.{
        .name = "netrunner-tui",
        .root_module = tui_module,
    });
    b.installArtifact(tui);

    const run_cmd = b.addRunArtifact(tui);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("tui", "Run the terminal UI");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
