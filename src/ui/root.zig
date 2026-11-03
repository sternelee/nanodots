//! The root layout: sidebar on the left, the page on the right.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const common = @import("common.zig");
const sidebar = @import("sidebar.zig");
const channel = @import("channel.zig");
const task = @import("task.zig");
const machine = @import("machine.zig");
const settings = @import("settings.zig");
const projects = @import("projects.zig");
const session = @import("session.zig");
const watch = @import("watch.zig");

pub fn view(s: *state_mod.State, c: *ui.Context) void {
    const root = ui.div(c).row().sizeFull().bg(common.hx(common.bg));
    defer root.end();
    sidebar.view(s, c);
    const main = ui.div(c).column().grow().hFull().minW(0);
    defer main.end();
    switch (s.page) {
        .channel => channel.view(s, c),
        .task => |index| task.view(s, c, index),
        .machine => |index| machine.view(s, c, index),
        .settings => settings.view(s, c),
        .projects => projects.listView(s, c),
        .project => |index| projects.detailView(s, c, index),
        .session => |index| session.view(s, c, index),
        .watchers => watch.listView(s, c),
        .watch => |index| watch.detailView(s, c, index),
    }
}
