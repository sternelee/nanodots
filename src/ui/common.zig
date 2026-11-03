//! Shared bits of the console's look: the film's dark palette, avatars,
//! chips, section labels and meter bars.
const std = @import("std");
const ui = @import("nanoui").ui;
const model = @import("../model.zig");

pub const bg = 0x17181c;
pub const sidebar_bg = 0x111216;
pub const card = 0x1e2026;
pub const card_hover = 0x262932;
pub const border = 0x2b2e36;
pub const text = 0xe8e8ec;
pub const muted = 0x8b8e98;
pub const faint = 0x5c5f68;
pub const orange = 0xd9a35b;
pub const green = 0x3fb950;
pub const blue = 0x58a6ff;
pub const red = 0xf85149;

pub fn hx(code: u24) ui.Color {
    return .hex(code);
}

/// The avatar disc: the agent's letter on its color.
pub fn avatar(c: *ui.Context, a: model.Agent, size: f32) void {
    const disc = ui.div(c).size(size, size).circular().bg(hx(a.color)).itemsCenter().justifyCenter();
    ui.text(c, c.print("{c}", .{a.letter}), .{ .size = size * 0.5, .weight = .semibold, .color = .white });
    disc.end();
}

/// A small rounded label on a dim background (decision ids, task statuses).
pub fn chip(c: *ui.Context, label: []const u8, fg: u24, bgc: u24) void {
    const d = ui.div(c).row().itemsCenter().px(7).py(2).rounded(5).bg(hx(bgc));
    ui.text(c, label, .{ .size = 11, .color = hx(fg) });
    d.end();
}

/// A section header in the sidebar ("待你决定", "进行中", …) with a count.
pub fn sectionLabel(c: *ui.Context, title: []const u8, count: ?usize, alert: bool) void {
    const row = ui.div(c).row().wFull().itemsCenter().justifyBetween().px(10).py(7);
    ui.text(c, title, .{ .size = 11, .color = hx(if (alert) orange else faint) });
    if (count) |n| {
        if (n > 0) ui.text(c, c.print("{d}", .{n}), .{ .size = 11, .color = hx(faint), .tabular = true });
    }
    row.end();
}

/// A horizontal meter: label row above, a track with the filled part.
pub fn meter(c: *ui.Context, label: []const u8, value: []const u8, pct: f32, width: f32, color: u24) void {
    const col = ui.div(c).column().w(width).gap(6);
    {
        const row = ui.div(c).row().wFull().itemsCenter().justifyBetween();
        ui.text(c, label, .{ .size = 12, .color = hx(muted) });
        ui.text(c, value, .{ .size = 12, .color = hx(text), .tabular = true });
        row.end();
    }
    const track = ui.div(c).wFull().h(5).roundedFull().bg(hx(0x33363e));
    const fill_w = @max(4, width * @min(1, @max(0, pct)));
    const fill = ui.div(c).w(fill_w).h(5).roundedFull().bg(hx(color));
    fill.end();
    track.end();
    col.end();
}

/// One row of the chat's progress timelines: "20:57  text"; failed steps
/// get a red marker, as in the film.
pub fn timelineRow(c: *ui.Context, line: []const u8) void {
    const row = ui.div(c).row().wFull().gap(8);
    const failed = std.mem.find(u8, line, "failure)") != null or std.mem.find(u8, line, "failed") != null;
    if (failed) {
        const dot = ui.div(c).size(6, 6).circular().bg(hx(red));
        dot.end();
    }
    var rest = line;
    var stamp: []const u8 = "";
    if (std.mem.findScalar(u8, line, ' ')) |space| {
        if (space == 5) {
            stamp = line[0..5];
            rest = line[6..];
        }
    }
    if (stamp.len > 0) {
        ui.text(c, stamp, .{ .size = 12, .color = hx(faint), .tabular = true });
    }
    ui.text(c, rest, .{ .size = 12.5, .color = if (failed) hx(0xd0a0a0) else hx(muted), .wrap = true, .leading = 1.35 });
    row.end();
}
