//! A project's interactive agent session, in the manner of fx cli or an
//! editor chat panel working in that directory: turns accumulate, the fx
//! session keeps its context across them, and tool calls show as cards.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const model = @import("../model.zig");
const common = @import("common.zig");
const channel = @import("channel.zig");

const State = state_mod.State;

pub fn view(s: *State, c: *ui.Context, index: usize) void {
    if (index >= s.projects.items.len) {
        s.page = .projects;
        return;
    }
    const entry = s.projects.items[index];
    const busy = entry.runtime.busy();
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    header(s, c, entry, index, busy);
    messages(c, entry);
    composer(s, c, entry, busy);
}

fn header(s: *State, c: *ui.Context, entry: *state_mod.ProjectEntry, index: usize, busy: bool) void {
    const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(11).border(common.hx(common.border));
    {
        const back = ui.div(c).row().itemsCenter().gap(6).px(7).py(3).rounded(6).hover(common.hx(common.card_hover));
        ui.text(c, "‹ 项目", .{ .size = 13, .color = common.hx(common.muted) });
        const clicked = back.clicked();
        back.end();
        if (clicked) s.page = .{ .project = index };
    }
    ui.text(c, c.print("{s} · agent 会话", .{entry.info.name}), .{ .size = 15, .weight = .semibold, .color = common.hx(common.text) });
    {
        const meta = ui.div(c).row().grow().itemsCenter().justifyEnd().gap(8);
        if (busy) {
            const dot = ui.div(c).size(7, 7).circular().bg(common.hx(common.orange));
            dot.end();
            ui.text(c, "运行中", .{ .size = 12, .color = common.hx(common.orange) });
            const stop = ui.div(c).row().itemsCenter().gap(4).px(9).py(3).rounded(7).bg(common.hx(0x3a2226)).hover(common.hx(0x4a2a30));
            ui.text(c, "× 中止", .{ .size = 12, .weight = .medium, .color = common.hx(common.red) });
            const clicked = stop.clicked();
            stop.end();
            if (clicked) entry.runtime.cancel();
        } else {
            const dot = ui.div(c).size(7, 7).circular().bg(common.hx(common.green));
            dot.end();
            ui.text(c, "空闲", .{ .size = 12, .color = common.hx(common.muted) });
        }
        ui.text(c, entry.info.path, .{ .size = 12, .color = common.hx(common.faint), .truncate = .ellipsis });
        meta.end();
    }
    row.end();
}

fn messages(c: *ui.Context, entry: *state_mod.ProjectEntry) void {
    _ = c.open(.{ .direction = .column, .width = .fill, .grow = 1, .scroll = true, .follow_end = true }, null);
    const col = ui.div(c).column().wFull().gap(14).p(18);
    if (entry.thread.items.len == 0) {
        ui.text(c, "在这里和 fx agent 对话，回合会在项目目录里执行。\n上下文跨回合保持，和 fx cli 会话一样。", .{ .size = 13, .color = common.hx(common.faint), .wrap = true, .leading = 1.5 });
    }
    for (entry.thread.items, 0..) |m, i| {
        ui.keyInt(c, i);
        switch (m.kind) {
            .note => channel.note(c, m),
            .owner => channel.owner(c, m),
            .tool => channel.toolRow(c, m),
            .diag => channel.diagRow(c, m),
            .decision => {},
        }
    }
    col.end();
    c.end();
}

fn composer(s: *State, c: *ui.Context, entry: *state_mod.ProjectEntry, busy: bool) void {
    const wrap = ui.div(c).column().wFull().p(14).border(common.hx(common.border));
    const box = ui.div(c).row().wFull().itemsCenter().gap(10).px(13).py(9).rounded(12).bg(common.hx(0x1b1d22)).border(common.hx(common.border)).hover(common.hx(0x1e2127));
    const result = ui.textField(c, &entry.input, .{
        .placeholder = if (busy) "agent 正在运行上一条…" else "和 agent 对话，例如：这个仓库怎么构建？",
        .width = .fill,
        .bare = true,
        .size = 13.5,
        .multiline = true,
        .max_lines = 5,
    });
    if (box.clicked()) entry.input.focus();
    const has_text = entry.input.text().len > 0;
    {
        const send = ui.div(c).row().itemsCenter().gap(4).px(10).py(4).rounded(7).bg(common.hx(if (has_text and !busy) 0x2f6feb else 0x24272f));
        ui.text(c, "发送 ↑", .{ .size = 12, .weight = .medium, .color = common.hx(if (has_text and !busy) 0xffffff else common.faint) });
        const clicked = send.clicked();
        send.end();
        if ((result.submitted or clicked) and !busy) s.sessionSubmit(entry);
    }
    box.end();
    wrap.end();
}
