//! A task's page: breadcrumb header with cancel, the meta line (role, host,
//! model, elapsed), then the request, the result and the progress timeline.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const model = @import("../model.zig");
const common = @import("common.zig");

const State = state_mod.State;

const status_color = [6]u24{
    common.green, // running
    common.blue, // queued
    common.orange, // waiting
    common.red, // failed
    common.faint, // done
    common.faint, // cancelled
};

pub fn view(s: *State, c: *ui.Context, index: usize) void {
    if (index >= s.tasks.items.len) {
        s.page = .channel;
        return;
    }
    const t = s.tasks.items[index];
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    header(s, c, index);
    const scroll = ui.div(c).column().wFull().grow().scrollY();
    const body = ui.div(c).column().wFull().gap(20).p(20);
    ui.text(c, t.title, .{ .size = 19, .weight = .bold, .color = common.hx(common.text), .wrap = true });
    section(c, "请求");
    paragraph(c, t.request);
    if (t.result.len > 0) {
        section(c, "结果");
        const row = ui.div(c).row().wFull().gap(8);
        if (t.result_status.len > 0) {
            const failed = std.mem.eql(u8, t.result_status, "failed");
            common.chip(c, t.result_status, if (failed) common.red else common.orange, 0x3a2c1c);
        }
        {
            const rest = ui.div(c).column().grow().minW(0);
            paragraph(c, t.result);
            rest.end();
        }
        row.end();
    }
    if (t.progress.len > 0) {
        section(c, "进度");
        const list = ui.div(c).column().wFull().gap(8);
        for (t.progress, 0..) |line, i| {
            ui.keyInt(c, i);
            common.timelineRow(c, line);
        }
        list.end();
    }
    body.end();
    scroll.end();
}

fn header(s: *State, c: *ui.Context, index: usize) void {
    const t = s.tasks.items[index];
    const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(11).border(common.hx(common.border));
    {
        const back = ui.div(c).row().itemsCenter().gap(6).px(7).py(3).rounded(6).hover(common.hx(common.card_hover));
        ui.text(c, "‹ 频道", .{ .size = 13, .color = common.hx(common.muted) });
        const clicked = back.clicked();
        back.end();
        if (clicked) s.page = .channel;
    }
    ui.text(c, c.print("任务 {s}", .{t.id}), .{ .size = 13, .weight = .medium, .color = common.hx(common.text) });
    {
        const meta = ui.div(c).row().grow().itemsCenter().justifyEnd().gap(8);
        common.chip(c, model.TaskStatus.label(t.status), status_color[@intFromEnum(t.status)], 0x24272f);
        ui.text(c, c.print("{s} · {s} · {s} · 已运行 {d} 分钟", .{ t.role, t.host, t.model, s.elapsedMinutes(index) }), .{ .size = 12, .color = common.hx(common.muted) });
        meta.end();
    }
    if (s.turn_task == index) {
        const cancel = ui.div(c).row().itemsCenter().gap(4).px(9).py(3).rounded(7).bg(common.hx(0x3a2226)).hover(common.hx(0x4a2a30));
        ui.text(c, "× 取消任务", .{ .size = 12, .weight = .medium, .color = common.hx(common.red) });
        const clicked = cancel.clicked();
        cancel.end();
        if (clicked) s.cancelTask(index);
    }
    row.end();
}

fn section(c: *ui.Context, title: []const u8) void {
    ui.text(c, title, .{ .size = 12, .weight = .semibold, .color = common.hx(common.faint) });
}

fn paragraph(c: *ui.Context, text: []const u8) void {
    const card = ui.div(c).column().wFull().p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    ui.text(c, text, .{ .size = 13, .color = common.hx(0xc9cbd2), .wrap = true, .leading = 1.5 });
    card.end();
}
