//! The watch pages: GitHub repos listened to for new PRs/issues. Each
//! watcher wakes the embedded agent on its interval (a Grok Bot-style
//! routine); the list page adds watchers, the detail page shows the
//! schedule, actions and the check transcript.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const model = @import("../model.zig");
const common = @import("common.zig");
const channel = @import("channel.zig");

const State = state_mod.State;

const intervals = [_]u32{ 5, 15, 30, 60 };

pub fn listView(s: *State, c: *ui.Context) void {
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    header(s, c, "监听", "仓库 · 定时检查新 PR / issue");
    const scroll = ui.div(c).column().wFull().grow().scrollY();
    const body = ui.div(c).column().wFull().gap(20).p(20);

    section(c, "添加监听");
    {
        const card = ui.div(c).column().wFull().gap(10).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
        ui.text(c, "GitHub 仓库", .{ .size = 12, .color = common.hx(common.muted) });
        {
            const box = ui.div(c).row().wFull().itemsCenter().gap(10).px(10).py(2).rounded(8).bg(common.hx(0x15171b)).border(common.hx(common.border));
            const result = ui.textField(c, &s.watch_repo, .{
                .placeholder = "owner/repo，例如 vercel-labs/fx",
                .width = .fill,
                .bare = true,
                .size = 13,
            });
            const add = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x2f6feb)).hover(common.hx(0x3a7dff));
            ui.text(c, "添加", .{ .size = 13, .weight = .medium, .color = .white });
            const clicked = add.clicked();
            add.end();
            if (result.submitted or clicked) s.addWatcher();
            box.end();
        }
        {
            const row = ui.div(c).row().wFull().itemsCenter().gap(8);
            ui.text(c, "检查目标", .{ .size = 12, .color = common.hx(common.muted) });
            if (toggleChip(c, "PR", s.watch_prs)) s.watch_prs = !s.watch_prs;
            if (toggleChip(c, "Issue", s.watch_issues)) s.watch_issues = !s.watch_issues;
            row.end();
        }
        {
            const row = ui.div(c).row().wFull().itemsCenter().gap(8);
            ui.text(c, "间隔", .{ .size = 12, .color = common.hx(common.muted) });
            for (intervals) |min| {
                if (intervalChip(c, min, s.watch_interval_min == min)) s.watch_interval_min = min;
            }
            row.end();
        }
        if (s.watch_note.len > 0) {
            ui.text(c, s.watch_note, .{ .size = 12, .color = common.hx(if (s.watch_note_err) common.red else common.green) });
        }
        ui.text(c, "到点 app 会唤醒内嵌 agent 用 gh 检查该仓库：首次检查建立基线，之后只汇报新出现的 PR/issue；没有新动态就安静结束，不打扰频道。", .{ .size = 12, .color = common.hx(common.faint), .wrap = true, .leading = 1.4 });
        card.end();
    }

    section(c, c.print("监听中 · {d}", .{s.watchers.items.len}));
    if (s.watchers.items.len == 0) {
        emptyRow(c, "还没有监听 — 在上方添加一个仓库");
    }
    const list = ui.div(c).column().wFull().gap(1).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    for (s.watchers.items, 0..) |entry, i| {
        ui.keyInt(c, i);
        const busy = entry.runtime.busy();
        const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(12).py(9).hover(common.hx(common.card_hover));
        {
            const dot = ui.div(c).size(7, 7).circular().bg(common.hx(if (busy) common.orange else if (entry.enabled) common.blue else common.faint));
            dot.end();
        }
        {
            const mid = ui.div(c).column().grow().minW(0).gap(2);
            ui.text(c, entry.info.repo, .{ .size = 13.5, .weight = .medium, .color = common.hx(common.text) });
            ui.text(c, c.print("每 {d} 分钟 · {s}", .{ entry.info.interval_min, scopeText(entry) }), .{ .size = 12, .color = common.hx(common.faint), .truncate = .ellipsis });
            mid.end();
        }
        {
            const right = ui.div(c).row().itemsCenter().justifyEnd().gap(8);
            if (!entry.enabled) {
                common.chip(c, "已暂停", common.faint, 0x24272f);
            } else if (busy) {
                common.chip(c, "检查中", common.orange, 0x3a2c1c);
            } else {
                ui.text(c, nextCheckText(c, entry), .{ .size = 11.5, .color = common.hx(common.faint), .tabular = true });
            }
            right.end();
        }
        const clicked = row.clicked();
        row.end();
        if (clicked) s.page = .{ .watch = i };
    }
    list.end();
    body.end();
    scroll.end();
}

pub fn detailView(s: *State, c: *ui.Context, index: usize) void {
    if (index >= s.watchers.items.len) {
        s.page = .watchers;
        return;
    }
    const entry = s.watchers.items[index];
    const busy = entry.runtime.busy();
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    {
        const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(11).border(common.hx(common.border));
        {
            const back = ui.div(c).row().itemsCenter().gap(6).px(7).py(3).rounded(6).hover(common.hx(common.card_hover));
            ui.text(c, "‹ 监听", .{ .size = 13, .color = common.hx(common.muted) });
            const clicked = back.clicked();
            back.end();
            if (clicked) s.page = .watchers;
        }
        {
            const title_row = ui.div(c).row().itemsCenter().gap(8);
            const dot = ui.div(c).size(8, 8).circular().bg(common.hx(if (busy) common.orange else if (entry.enabled) common.blue else common.faint));
            dot.end();
            ui.text(c, entry.info.repo, .{ .size = 15, .weight = .semibold, .color = common.hx(common.text) });
            title_row.end();
        }
        {
            const meta = ui.div(c).row().grow().itemsCenter().justifyEnd().gap(6);
            common.chip(c, c.print("每 {d} 分钟", .{entry.info.interval_min}), common.blue, 0x1c2b3a);
            common.chip(c, scopeText(entry), common.muted, 0x24272f);
            if (busy) {
                ui.text(c, "检查中", .{ .size = 12, .color = common.hx(common.orange) });
            } else if (!entry.enabled) {
                ui.text(c, "已暂停", .{ .size = 12, .color = common.hx(common.faint) });
            } else {
                ui.text(c, "空闲", .{ .size = 12, .color = common.hx(common.muted) });
            }
            meta.end();
        }
        row.end();
    }
    {
        const top = ui.div(c).column().wFull().gap(12).p(20);
        section(c, "状态");
        {
            const card = ui.div(c).column().wFull().gap(8).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
            statusRow(c, "上次检查", if (entry.last_check_ms > 0) c.print("{s}", .{state_mod.hhmm(&watch_time_buf, entry.last_check_ms)}) else "从未");
            statusRow(c, "上次结论", if (entry.last_result.len > 0) entry.last_result else "—");
            statusRow(c, "下次检查", if (entry.enabled) nextCheckText(c, entry) else "已暂停");
            statusRow(c, "累计", c.print("检查 {d} 次 · 发现 {d} 次", .{ entry.checks, entry.findings }));
            card.end();
        }
        section(c, "操作");
        {
            const row = ui.div(c).row().wFull().itemsCenter().gap(10).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
            {
                const button = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(if (busy) 0x24272f else 0x2f6feb)).hover(common.hx(if (busy) 0x24272f else 0x3a7dff));
                ui.text(c, "立即检查", .{ .size = 13, .weight = .medium, .color = common.hx(if (busy) common.faint else 0xffffff) });
                const clicked = button.clicked();
                button.end();
                if (clicked and !busy) s.checkWatcherNow(index);
            }
            {
                const button = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x24272f)).hover(common.hx(0x2b2f38));
                ui.text(c, if (entry.enabled) "暂停" else "启用", .{ .size = 13, .weight = .medium, .color = common.hx(common.muted) });
                const clicked = button.clicked();
                button.end();
                if (clicked) s.toggleWatcher(index);
            }
            {
                const remove = ui.div(c).row().itemsCenter().gap(4).px(9).py(3).rounded(7).bg(common.hx(0x3a2226)).hover(common.hx(0x4a2a30));
                ui.text(c, "× 移除", .{ .size = 12, .weight = .medium, .color = common.hx(common.red) });
                const clicked = remove.clicked();
                remove.end();
                if (clicked) s.removeWatcher(index);
            }
            row.end();
        }
        top.end();
    }
    transcript(c, entry);
}

var watch_time_buf: [8]u8 = undefined;

fn transcript(c: *ui.Context, entry: *state_mod.WatchEntry) void {
    sectionPadded(c, "检查记录");
    _ = c.open(.{ .direction = .column, .width = .fill, .grow = 1, .scroll = true, .follow_end = true }, null);
    const col = ui.div(c).column().wFull().gap(14).p(18);
    if (entry.thread.items.len == 0) {
        ui.text(c, "还没有检查记录。首次检查会在添加后约 1 秒内开始。", .{ .size = 13, .color = common.hx(common.faint), .wrap = true, .leading = 1.5 });
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

fn statusRow(c: *ui.Context, label: []const u8, value: []const u8) void {
    const row = ui.div(c).row().wFull().itemsCenter().gap(10);
    {
        const l = ui.div(c).row().w(72);
        ui.text(c, label, .{ .size = 12, .color = common.hx(common.faint) });
        l.end();
    }
    {
        const v = ui.div(c).column().grow().minW(0);
        ui.text(c, value, .{ .size = 12.5, .color = common.hx(common.muted), .wrap = true, .leading = 1.35 });
        v.end();
    }
    row.end();
}

fn scopeText(entry: *state_mod.WatchEntry) []const u8 {
    if (entry.info.watch_prs and entry.info.watch_issues) return "PR + Issue";
    if (entry.info.watch_prs) return "PR";
    return "Issue";
}

fn nextCheckText(c: *ui.Context, entry: *state_mod.WatchEntry) []const u8 {
    if (entry.runtime.busy()) return "检查中";
    const now_ms = @import("fx").shared_io.milliTimestamp();
    const mins = @divFloor(entry.next_fire_ms - now_ms + 59_999, 60_000);
    if (mins <= 0) return "即将";
    return c.print("{d} 分钟后", .{mins});
}

/// A clickable on/off chip; returns whether it was clicked this frame.
fn toggleChip(c: *ui.Context, label: []const u8, on: bool) bool {
    const d = ui.div(c).row().itemsCenter().px(9).py(3).rounded(6).bg(common.hx(if (on) 0x1c2b3a else 0x24272f)).hover(common.hx(common.card_hover));
    ui.text(c, label, .{ .size = 12, .weight = if (on) .medium else .regular, .color = common.hx(if (on) common.blue else common.faint) });
    const clicked = d.clicked();
    d.end();
    return clicked;
}

fn intervalChip(c: *ui.Context, min: u32, on: bool) bool {
    const d = ui.div(c).row().itemsCenter().px(9).py(3).rounded(6).bg(common.hx(if (on) 0x1c2b3a else 0x24272f)).hover(common.hx(common.card_hover));
    ui.text(c, c.print("{d} 分钟", .{min}), .{ .size = 12, .weight = if (on) .medium else .regular, .color = common.hx(if (on) common.blue else common.faint) });
    const clicked = d.clicked();
    d.end();
    return clicked;
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

fn sectionPadded(c: *ui.Context, title: []const u8) void {
    const row = ui.div(c).row().wFull().px(20).pt(4).pb(8);
    ui.text(c, title, .{ .size = 12, .weight = .semibold, .color = common.hx(common.faint) });
    row.end();
}

fn emptyRow(c: *ui.Context, text: []const u8) void {
    const row = ui.div(c).row().wFull().px(13).py(9).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    ui.text(c, text, .{ .size = 12.5, .color = common.hx(common.faint) });
    row.end();
}
