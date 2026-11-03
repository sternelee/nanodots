//! A host's page: online status, load, memory and disk meters, the tools and
//! accounts it carries, and the tasks running and finished on it.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const model = @import("../model.zig");
const common = @import("common.zig");

const State = state_mod.State;

pub fn view(s: *State, c: *ui.Context, index: usize) void {
    if (index >= s.machines.items.len) {
        s.page = .channel;
        return;
    }
    const m = s.machines.items[index];
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    header(s, c, m);
    const scroll = ui.div(c).column().wFull().grow().scrollY();
    const body = ui.div(c).column().wFull().gap(20).p(20);

    section(c, "资源");
    if (m.online) {
        const meters = ui.div(c).row().wFull().gap(14);
        const load_color: u24 = if (m.load_pct >= 80) common.orange else common.green;
        common.meter(c, "负载", c.print("{d}% · {d} 核", .{ m.load_pct, m.cores }), @as(f32, @floatFromInt(m.load_pct)) / 100, 220, load_color);
        common.meter(c, "内存", c.print("已用 {d}%", .{m.mem_pct}), @as(f32, @floatFromInt(m.mem_pct)) / 100, 220, common.green);
        common.meter(c, "磁盘", c.print("剩余 {d} GB", .{m.disk_free_gb}), @as(f32, @floatFromInt(m.disk_free_gb)) / 2000, 220, common.green);
        meters.end();
    } else {
        const note = ui.div(c).row().wFull().px(13).py(9).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
        ui.text(c, c.print("机器离线，最后心跳 {s}，无实时资源数据", .{m.heartbeat}), .{ .size = 13, .color = common.hx(common.muted) });
        note.end();
    }

    section(c, "工具与账号");
    {
        const tools = ui.div(c).row().wFull().gap(8);
        for (m.tools) |tool| {
            const chip_div = ui.div(c).row().itemsCenter().px(10).py(4).rounded(7).bg(common.hx(0x24272f)).border(common.hx(common.border));
            ui.text(c, tool, .{ .size = 12.5, .color = common.hx(0xc9cbd2) });
            chip_div.end();
        }
        tools.end();
    }

    taskList(s, c, m, "运行中", true);
    taskList(s, c, m, "最近", false);
    body.end();
    scroll.end();
}

fn header(s: *State, c: *ui.Context, m: model.Machine) void {
    const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(11).border(common.hx(common.border));
    {
        const back = ui.div(c).row().itemsCenter().gap(6).px(7).py(3).rounded(6).hover(common.hx(common.card_hover));
        ui.text(c, "‹ 频道", .{ .size = 13, .color = common.hx(common.muted) });
        const clicked = back.clicked();
        back.end();
        if (clicked) s.page = .channel;
    }
    {
        const title_row = ui.div(c).row().itemsCenter().gap(8);
        const dot = ui.div(c).size(8, 8).circular().bg(common.hx(if (m.online) common.green else common.faint));
        dot.end();
        ui.text(c, m.name, .{ .size = 15, .weight = .semibold, .color = common.hx(common.text) });
        if (!m.online) common.chip(c, "离线", common.red, 0x3a2226);
        title_row.end();
    }
    {
        const meta = ui.div(c).row().grow().itemsCenter().justifyEnd();
        ui.text(c, if (m.online) c.print("{s} · 在线 · 心跳 {s} · {d} 个运行中", .{ m.kind, m.heartbeat, countRunning(s, m.name) }) else c.print("{s} · 离线 · 最后心跳 {s}", .{ m.kind, m.heartbeat }), .{ .size = 12, .color = common.hx(common.muted) });
        meta.end();
    }
    row.end();
}

fn section(c: *ui.Context, title: []const u8) void {
    ui.text(c, title, .{ .size = 12, .weight = .semibold, .color = common.hx(common.faint) });
}

fn taskList(s: *State, c: *ui.Context, m: model.Machine, title: []const u8, running: bool) void {
    section(c, title);
    const list = ui.div(c).column().wFull().gap(1).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    var any = false;
    for (s.tasks.items, 0..) |t, i| {
        const on_host = std.mem.eql(u8, t.host, m.name);
        const in_section = if (running) t.status == .running and on_host else (t.status == .done and on_host);
        if (!in_section) continue;
        any = true;
        ui.keyInt(c, i);
        const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(12).py(8).hover(common.hx(common.card_hover));
        if (!running) {
            ui.text(c, "✓", .{ .size = 12, .color = common.hx(common.green) });
        } else {
            const dot = ui.div(c).size(6, 6).circular().bg(common.hx(common.green));
            dot.end();
        }
        {
            const title_div = ui.div(c).column().grow();
            ui.text(c, t.title, .{ .size = 13, .color = common.hx(0xc9cbd2), .truncate = .ellipsis });
            title_div.end();
        }
        {
            const right = ui.div(c).row().itemsCenter().justifyEnd().gap(10);
            ui.text(c, t.role, .{ .size = 11.5, .color = common.hx(common.faint) });
            ui.text(c, c.print("{d} 分钟", .{s.elapsedMinutes(i)}), .{ .size = 11.5, .color = common.hx(common.faint), .tabular = true });
            right.end();
        }
        const clicked = row.clicked();
        row.end();
        if (clicked) s.page = .{ .task = i };
    }
    if (!any) {
        const row = ui.div(c).row().wFull().px(12).py(8);
        ui.text(c, "无", .{ .size = 12, .color = common.hx(common.faint) });
        row.end();
    }
    list.end();
}

fn countRunning(s: *State, host: []const u8) usize {
    var n: usize = 0;
    for (s.tasks.items) |t| {
        if (t.status == .running and std.mem.eql(u8, t.host, host)) n += 1;
    }
    return n;
}
