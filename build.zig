const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "SparrowPacker",
        .root_module = exe_mod,
    });

    // raylib
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    // zig bindings
    const raylib = raylib_dep.module("raylib");
    exe.root_module.addImport("raylib", raylib);

    // custom c shit
    const raylib_artifact = raylib_dep.artifact("raylib");
    raylib_artifact.root_module.addCMacro("SUPPORT_FILEFORMAT_FLAC", "1");
    // raylib_artifact.root_module.addCMacro("SUPPORT_BUSY_WAIT_LOOP", "1");
    exe.linkLibrary(raylib_artifact);

    // raygui
    const raygui = raylib_dep.module("raygui");
    exe.root_module.addImport("raygui", raygui);

    // xml
    const xml_dep = b.dependency("xml", .{
        .target = target,
        .optimize = optimize,
    });
    const xml = xml_dep.module("xml");
    exe.root_module.addImport("xml", xml);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
