//! nanodot: a noop-style console for a team of embedded fx agents, built on
//! nanoui. The UI is the film's three pages (channel, task, machine); the
//! composer dispatches instructions to the fx agent compiled into the app.
const std = @import("std");
const nanoui = @import("nanoui");
const engine = @import("fx");
const state_mod = @import("state.zig");

pub fn main(init: std.process.Init) !void {
    // fx's tool children re-execute this binary for private helpers; when the
    // args say so, run that and nothing else.
    if (try engine.runInternal(init)) return;
    // The agent reads HOME, PATH and provider credentials from the launch
    // environment, as nanoterm's main does.
    engine.shared_io.setEnvironMap(init.environ_map);

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) {
        var buf: [64]u8 = undefined;
        var w = std.Io.File.stdout().writerStreaming(init.io, &buf);
        w.interface.print("nanodot {s}\n", .{@import("build_options").version}) catch {};
        w.interface.flush() catch {};
        return;
    }

    const app = try nanoui.App.create(init, .{ .name = "nanodot" });
    defer app.destroy();
    const state = try state_mod.State.create();
    defer state.destroy();
    const window = try app.newWindow(.{
        .title = "nanodot",
        .width = 1312,
        .height = 912,
        .min_width = 960,
        .min_height = 640,
        .theme = nanoui.ui.Theme.dark_theme,
        .content = .{ .view = .init(state, state_mod.State.view) },
    });
    state.window = window;
    try app.run();
}

test "seed data loads" {
    const state = try state_mod.State.create();
    defer state.destroy();
    try std.testing.expect(state.decisions.items.len >= 3);
    try std.testing.expect(state.tasks.items.len >= 8);
    try std.testing.expect(state.machines.items.len == 3);
    try std.testing.expect(state.messages.items.len >= 5);
    state.choose(2, 0);
    try std.testing.expect(state.decisions.items[2].choice != null);
}
