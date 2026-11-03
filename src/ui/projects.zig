//! The projects pages: the list (with the add form) and one project's page.
//! A project is a workspace directory the owner added; instructions from the
//! composer run in the selected project's directory, each project keeping
//! its own fx session.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const model = @import("../model.zig");
const common = @import("common.zig");

const State = state_mod.State;

pub fn listView(s: *State, c: *ui.Context) void {
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    header(s, c, "项目", "工作区 · 在下方添加目录");
    const scroll = ui.div(c).column().wFull().grow().scrollY();
    const body = ui.div(c).column().wFull().gap(20).p(20);

    section(c, "添加项目");
    {
        const card = ui.div(c).column().wFull().gap(10).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
        ui.text(c, "目录路径", .{ .size = 12, .color = common.hx(common.muted) });
        {
            const box = ui.div(c).row().wFull().itemsCenter().gap(10).px(10).py(2).rounded(8).bg(common.hx(0x15171b)).border(common.hx(common.border));
            const result = ui.textField(c, &s.add_path, .{
                .placeholder = "~/work/nsh 或 /abs/path/to/repo",
                .width = .fill,
                .bare = true,
                .size = 13,
            });
            const add = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x2f6feb)).hover(common.hx(0x3a7dff));
            ui.text(c, "添加", .{ .size = 13, .weight = .medium, .color = .white });
            const clicked = add.clicked();
            add.end();
            if (result.submitted or clicked) s.addProject();
            box.end();
        }
        if (s.add_note.len > 0) {
            ui.text(c, s.add_note, .{ .size = 12, .color = common.hx(if (s.add_note_err) common.red else common.green) });
        }
        ui.text(c, "添加后自动设为任务目标：在频道输入框下达的指令会在该目录里执行，项目拥有独立的 fx 会话。", .{ .size = 12, .color = common.hx(common.faint), .wrap = true, .leading = 1.4 });
        card.end();
    }

    section(c, c.print("已有项目 · {d}", .{s.projects.items.len}));
    if (s.projects.items.len == 0) {
        emptyRow(c, "还没有项目");
    }
    const list = ui.div(c).column().wFull().gap(1).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    for (s.projects.items, 0..) |entry, i| {
        ui.keyInt(c, i);
        const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(12).py(9).hover(common.hx(common.card_hover));
        {
            const dot = ui.div(c).size(7, 7).circular().bg(common.hx(if (s.target == i) common.green else common.blue));
            dot.end();
        }
        {
            const mid = ui.div(c).column().grow().minW(0).gap(2);
            ui.text(c, entry.info.name, .{ .size = 13.5, .weight = .medium, .color = common.hx(common.text) });
            ui.text(c, entry.info.path, .{ .size = 12, .color = common.hx(common.faint), .truncate = .ellipsis });
            mid.end();
        }
        if (s.target == i) common.chip(c, "目标", common.green, 0x233628);
        const clicked = row.clicked();
        row.end();
        if (clicked) {
            s.target = i;
            s.page = .{ .project = i };
        }
    }
    list.end();
    body.end();
    scroll.end();
}

pub fn detailView(s: *State, c: *ui.Context, index: usize) void {
    if (index >= s.projects.items.len) {
        s.page = .projects;
        return;
    }
    const entry = s.projects.items[index];
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    {
        const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(11).border(common.hx(common.border));
        {
            const back = ui.div(c).row().itemsCenter().gap(6).px(7).py(3).rounded(6).hover(common.hx(common.card_hover));
            ui.text(c, "‹ 项目", .{ .size = 13, .color = common.hx(common.muted) });
            const clicked = back.clicked();
            back.end();
            if (clicked) s.page = .projects;
        }
        {
            const title_row = ui.div(c).row().itemsCenter().gap(8);
            const dot = ui.div(c).size(8, 8).circular().bg(common.hx(common.blue));
            dot.end();
            ui.text(c, entry.info.name, .{ .size = 15, .weight = .semibold, .color = common.hx(common.text) });
            if (s.target == index) common.chip(c, "目标", common.green, 0x233628);
            title_row.end();
        }
        {
            const meta = ui.div(c).row().grow().itemsCenter().justifyEnd();
            ui.text(c, entry.info.path, .{ .size = 12, .color = common.hx(common.muted), .truncate = .ellipsis });
            meta.end();
        }
        row.end();
    }
    const scroll = ui.div(c).column().wFull().grow().scrollY();
    const body = ui.div(c).column().wFull().gap(20).p(20);

    section(c, "操作");
    {
        const card = ui.div(c).row().wFull().itemsCenter().gap(10).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
        if (s.target == index) {
            const chip_div = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x233628));
            ui.text(c, "✓ 已是任务目标", .{ .size = 13, .weight = .medium, .color = common.hx(common.green) });
            chip_div.end();
            ui.text(c, "在频道输入框下达的指令会在此目录中执行。", .{ .size = 12.5, .color = common.hx(common.muted) });
        } else {
            const button = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x2f6feb)).hover(common.hx(0x3a7dff));
            ui.text(c, "设为目标", .{ .size = 13, .weight = .medium, .color = .white });
            const clicked = button.clicked();
            button.end();
            if (clicked) s.target = index;
        }
        {
            const remove = ui.div(c).row().itemsCenter().gap(4).px(9).py(3).rounded(7).bg(common.hx(0x3a2226)).hover(common.hx(0x4a2a30));
            ui.text(c, "× 移除项目", .{ .size = 12, .weight = .medium, .color = common.hx(common.red) });
            const clicked = remove.clicked();
            remove.end();
            if (clicked) s.removeProject(index);
        }
        card.end();
    }

    section(c, c.print("此项目的任务 · {d}", .{countProjectTasks(s, index)}));
    if (countProjectTasks(s, index) == 0) {
        emptyRow(c, "还没有任务 — 在频道里给团队下指令");
    }
    const list = ui.div(c).column().wFull().gap(1).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    for (s.tasks.items, 0..) |t, i| {
        if (t.project != index) continue;
        ui.keyInt(c, i);
        const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(12).py(8).hover(common.hx(common.card_hover));
        {
            const dot = ui.div(c).size(6, 6).circular().bg(common.hx(switch (t.status) {
                .running => common.green,
                .queued => common.blue,
                .waiting => common.orange,
                .failed, .cancelled => common.red,
                .done => common.faint,
            }));
            dot.end();
        }
        {
            const title_div = ui.div(c).column().grow();
            ui.text(c, t.title, .{ .size = 13, .color = common.hx(0xc9cbd2), .truncate = .ellipsis });
            title_div.end();
        }
        {
            const right = ui.div(c).row().itemsCenter().justifyEnd().gap(10);
            ui.text(c, model.TaskStatus.label(t.status), .{ .size = 11.5, .color = common.hx(common.faint) });
            right.end();
        }
        const clicked = row.clicked();
        row.end();
        if (clicked) s.page = .{ .task = i };
    }
    list.end();
    body.end();
    scroll.end();
}

fn countProjectTasks(s: *State, index: usize) usize {
    var n: usize = 0;
    for (s.tasks.items) |t| {
        if (t.project == index) n += 1;
    }
    return n;
}

fn header(s: *State, c: *ui.Context, title: []const u8, subtitle: []const u8) void {
    const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(11).border(common.hx(common.border));
    {
        const back = ui.div(c).row().itemsCenter().gap(6).px(7).py(3).rounded(6).hover(common.hx(common.card_hover));
        ui.text(c, "‹ 频道", .{ .size = 13, .color = common.hx(common.muted) });
        const clicked = back.clicked();
        back.end();
        if (clicked) s.page = .channel;
    }
    ui.text(c, title, .{ .size = 15, .weight = .semibold, .color = common.hx(common.text) });
    {
        const meta = ui.div(c).row().grow().itemsCenter().justifyEnd();
        ui.text(c, subtitle, .{ .size = 12, .color = common.hx(common.muted) });
        meta.end();
    }
    row.end();
}

fn section(c: *ui.Context, title: []const u8) void {
    ui.text(c, title, .{ .size = 12, .weight = .semibold, .color = common.hx(common.faint) });
}

fn emptyRow(c: *ui.Context, text: []const u8) void {
    const row = ui.div(c).row().wFull().px(13).py(9).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    ui.text(c, text, .{ .size = 12.5, .color = common.hx(common.faint) });
    row.end();
}