//! The left rail: channels, decisions waiting on the owner, live tasks,
//! queued and recent work, and the fleet of agent hosts.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const model = @import("../model.zig");
const common = @import("common.zig");

const State = state_mod.State;

pub fn view(s: *State, c: *ui.Context) void {
    const bar = ui.div(c).column().w(272).hFull().bg(common.hx(common.sidebar_bg)).border(common.hx(common.border));
    defer bar.end();
    channels(s, c);
    projectsSection(s, c);
    decisions(s, c);
    tasks(s, c);
    machines(s, c);
    footer(s, c);
}

fn channels(s: *State, c: *ui.Context) void {
    const col = ui.div(c).column().wFull().py(10).gap(1);
    channelRow(c, "团队频道", c.print("{d} 待决定", .{s.pendingCount()}), true);
    channelRow(c, "团队规则与记忆", "", false);
    col.end();
}

fn channelRow(c: *ui.Context, title: []const u8, suffix: []const u8, active: bool) void {
    const row = ui.div(c).row().wFull().itemsCenter().justifyBetween().px(10).py(6).hover(common.hx(common.card_hover));
    const label_row = ui.div(c).row().itemsCenter().gap(8);
    ui.text(c, title, .{ .size = 13, .color = common.hx(if (active) common.text else common.muted), .weight = if (active) .medium else .regular });
    label_row.end();
    if (suffix.len > 0) ui.text(c, suffix, .{ .size = 11, .color = common.hx(common.faint) });
    row.end();
}

fn projectsSection(s: *State, c: *ui.Context) void {
    common.sectionLabel(c, "项目", s.projects.items.len, false);
    for (s.projects.items, 0..) |entry, i| {
        ui.keyInt(c, 8000 + i);
        const active = switch (s.page) {
            .project => |pi| pi == i,
            else => false,
        };
        const base: ui.Color = if (active) common.hx(0x23262e) else common.hx(common.sidebar_bg);
        const row = ui.div(c).row().wFull().itemsCenter().gap(8).px(10).py(5).bg(base).hover(common.hx(common.card_hover));
        {
            const dot = ui.div(c).size(6, 6).circular().bg(common.hx(if (s.target == i) common.green else common.blue));
            dot.end();
        }
        {
            const name_div = ui.div(c).column().grow();
            ui.text(c, entry.info.name, .{ .size = 12.5, .color = common.hx(if (active) common.text else common.muted), .truncate = .ellipsis, .weight = if (active) .medium else .regular });
            name_div.end();
        }
        {
            const suffix_div = ui.div(c).row().justifyEnd();
            ui.text(c, if (s.target == i) "目标" else "", .{ .size = 11, .color = common.hx(common.green) });
            suffix_div.end();
        }
        const clicked = row.clicked();
        row.end();
        if (clicked) {
            s.target = i;
            s.page = .{ .project = i };
        }
    }
    if (item(c, "＋ 添加项目", "", common.faint, s.page == .projects)) s.page = .projects;
}

fn decisions(s: *State, c: *ui.Context) void {
    common.sectionLabel(c, "待你决定", s.pendingCount(), true);
    for (s.decisions.items, 0..) |d, i| {
        if (d.choice != null) continue;
        ui.keyInt(c, 1000 + i);
        if (item(c, d.title, d.id, common.orange, false)) s.page = .channel;
    }
}

fn tasks(s: *State, c: *ui.Context) void {
    common.sectionLabel(c, "进行中", s.runningCount(), false);
    for (s.tasks.items, 0..) |t, i| {
        if (t.status != .running) continue;
        ui.keyInt(c, 2000 + i);
        const suffix = c.print("{d} 分钟", .{s.elapsedMinutes(i)});
        if (item(c, t.title, suffix, common.green, pageIsTask(s, i))) s.page = .{ .task = i };
    }

    common.sectionLabel(c, "排队", countStatus(s, .queued), false);
    for (s.tasks.items, 0..) |t, i| {
        if (t.status != .queued) continue;
        ui.keyInt(c, 3000 + i);
        if (item(c, t.title, "排队中", common.blue, pageIsTask(s, i))) s.page = .{ .task = i };
    }

    common.sectionLabel(c, "最近", null, false);
    for (s.tasks.items, 0..) |t, i| {
        if (t.status != .done and t.status != .waiting and t.status != .failed and t.status != .cancelled) continue;
        ui.keyInt(c, 4000 + i);
        const suffix = if (t.status == .done)
            c.print("{d} 分钟", .{t.started_min_ago})
        else
            model.TaskStatus.label(t.status);
        if (item(c, t.title, suffix, common.faint, pageIsTask(s, i))) s.page = .{ .task = i };
    }
}

/// One clickable sidebar row; returns whether it was clicked this frame.
fn item(c: *ui.Context, title: []const u8, suffix: []const u8, dot: u24, active: bool) bool {
    const base: ui.Color = if (active) common.hx(0x23262e) else common.hx(common.sidebar_bg);
    const row = ui.div(c).row().wFull().itemsCenter().gap(8).px(10).py(5).bg(base).hover(common.hx(common.card_hover));
    {
        const dot_div = ui.div(c).size(6, 6).circular().bg(common.hx(dot));
        dot_div.end();
    }
    {
        const title_div = ui.div(c).column().grow();
        ui.text(c, title, .{ .size = 12.5, .color = common.hx(if (active) common.text else common.muted), .truncate = .ellipsis, .weight = if (active) .medium else .regular });
        title_div.end();
    }
    {
        const suffix_div = ui.div(c).row().justifyEnd();
        ui.text(c, suffix, .{ .size = 11, .color = common.hx(common.faint), .tabular = true });
        suffix_div.end();
    }
    const clicked = row.clicked();
    row.end();
    return clicked;
}

fn pageIsTask(s: *State, index: usize) bool {
    return switch (s.page) {
        .task => |i| i == index,
        else => false,
    };
}

fn pageIsMachine(s: *State, index: usize) bool {
    return switch (s.page) {
        .machine => |i| i == index,
        else => false,
    };
}

fn machines(s: *State, c: *ui.Context) void {
    var online: usize = 0;
    for (s.machines.items) |m| {
        if (m.online) online += 1;
    }
    common.sectionLabel(c, "机器", online, false);
    for (s.machines.items, 0..) |m, i| {
        ui.keyInt(c, 5000 + i);
        const base: ui.Color = if (pageIsMachine(s, i)) common.hx(0x23262e) else common.hx(common.sidebar_bg);
        const row = ui.div(c).row().wFull().itemsCenter().gap(8).px(10).py(5).bg(base).hover(common.hx(common.card_hover));
        {
            const dot_div = ui.div(c).size(6, 6).circular().bg(common.hx(if (m.online) common.green else common.faint));
            dot_div.end();
        }
        {
            const name_div = ui.div(c).column().grow();
            ui.text(c, m.name, .{ .size = 12.5, .color = common.hx(if (m.online) common.muted else common.faint), .truncate = .ellipsis });
            name_div.end();
        }
        {
            const suffix_div = ui.div(c).row().justifyEnd();
            ui.text(c, if (m.online) c.print("{d} 运行中", .{countRunning(s, m.name)}) else "离线", .{ .size = 11, .color = common.hx(if (m.online) common.faint else common.red) });
            suffix_div.end();
        }
        const clicked = row.clicked();
        row.end();
        if (clicked) s.page = .{ .machine = i };
    }
    const stats = ui.div(c).row().wFull().px(10).py(6);
    ui.text(c, c.print("排队 {d} · 阻塞 {d} · 失败 {d}", .{ countStatus(s, .queued), countStatus(s, .waiting), countStatus(s, .failed) }), .{ .size = 11, .color = common.hx(common.faint) });
    stats.end();
}

fn countRunning(s: *State, host: []const u8) usize {
    var n: usize = 0;
    for (s.tasks.items) |t| {
        if (t.status == .running and std.mem.eql(u8, t.host, host)) n += 1;
    }
    return n;
}

fn countStatus(s: *State, status: model.TaskStatus) usize {
    var n: usize = 0;
    for (s.tasks.items) |t| {
        if (t.status == status) n += 1;
    }
    return n;
}

fn footer(s: *State, c: *ui.Context) void {
    const top = ui.div(c).column().wFull().grow().justifyEnd();
    const row = ui.div(c).row().wFull().itemsCenter().justifyBetween().px(12).py(9).border(common.hx(common.border));
    const left = ui.div(c).column().gap(2);
    ui.text(c, "团队频道", .{ .size = 12, .weight = .medium, .color = common.hx(common.text) });
    ui.text(c, "noop.allsun.io", .{ .size = 11, .color = common.hx(common.faint) });
    left.end();
    {
        const gear = ui.div(c).row().itemsCenter().px(7).py(2).rounded(6).hover(common.hx(common.card_hover));
        ui.text(c, "⚙", .{ .size = 14, .color = common.hx(if (s.page == .settings) common.text else common.muted) });
        const clicked = gear.clicked();
        gear.end();
        if (clicked) s.page = .settings;
    }
    row.end();
    top.end();
}
