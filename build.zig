const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raknet = b.addModule("zenith-raknet", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag != .freestanding,
    });

    const zenith_raknet_lib = b.addLibrary(.{
        .name = "zenith-raknet",
        .root_module = raknet,
        .linkage = .static,
    });
    b.installArtifact(zenith_raknet_lib);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = zenith_raknet_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    const mod_tests = b.addTest(.{
        .root_module = raknet,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
