const std = @import("std");

// nanodot: a noop-style console for a team of embedded fx agents, built on
// nanoui. The agent engine is the same embedded fx runtime nanoterm compiles
// in (vercel-labs/fx, patched by nanoterm's prepare-fx.sh), referenced from
// the sibling nanoterm checkout so the fx submodule stays single-sourced.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize }).module("nanoui");
    // Where the embedded fx entry point (nanoterm's patch applied) lives.
    const fx_root = b.option([]const u8, "fx-root", "Path to the fx checkout with nanoterm's embedded.zig") orelse "../nanoterm/vendor/fx";
    const fx_src = b.pathJoin(&.{ fx_root, "src", "embedded.zig" });

    const options = b.addOptions();
    options.addOption([]const u8, "version", b.option([]const u8, "version", "nanodot's version (release builds)") orelse "");

    // fx's modules import these three names; the values mirror nanoterm's.
    const fx_options = b.addOptions();
    fx_options.addOption([]const u8, "git_commit", "embedded");
    fx_options.addOption([]const u8, "app_version", "embedded");
    fx_options.addOption([]const u8, "update_channel", "stable");
    fx_options.addOption(enum { none, core, term }, "wasm_surface", .none);
    fx_options.addOption(bool, "libfx", false);
    fx_options.addOption(bool, "builtin_tools", true);
    const session_options = b.addOptions();
    session_options.addOption(bool, "hooks", false);
    session_options.addOptionPathUntracked("trace_dir", b.graph.path(.install_prefix, "session-manager-traces"));
    session_options.addOptionPathUntracked("src_dir", .{ .cwd_relative = b.pathJoin(&.{ fx_root, "src", "core", "session_manager" }) });
    const session_manager = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ fx_root, "src", "core", "session_manager", "api.zig" }) },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "build_options", .module = session_options.createModule() }},
    });
    const test_paths = b.addOptions();
    test_paths.addOptionPathUntracked("product_exe", b.graph.path(.install_bin, "nanodot"));
    test_paths.addOptionPathUntracked("source_root", .{ .cwd_relative = b.pathJoin(&.{ fx_root, "src" }) });
    const fx = b.createModule(.{
        .root_source_file = .{ .cwd_relative = fx_src },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "build_options", .module = fx_options.createModule() },
            .{ .name = "session_manager", .module = session_manager },
            .{ .name = "test_paths", .module = test_paths.createModule() },
        },
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{ .{ .name = "nanoui", .module = nanoui }, .{ .name = "build_options", .module = options.createModule() }, .{ .name = "fx", .module = fx } },
    });
    const exe = b.addExecutable(.{ .name = "nanodot", .root_module = mod });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run nanodot").dependOn(&run.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{ .{ .name = "nanoui", .module = nanoui }, .{ .name = "build_options", .module = options.createModule() }, .{ .name = "fx", .module = fx } },
        }),
    });
    b.step("test", "Run nanodot's tests").dependOn(&b.addRunArtifact(tests).step);
}
