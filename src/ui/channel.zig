//! The team channel: the header with its pending-decision pill, the message
//! stream (agent reports, decision cards, the owner's right-aligned
//! replies), and the composer at the bottom.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const model = @import("../model.zig");
const common = @import("common.zig");

const State = state_mod.State;

pub fn view(s: *State, c: *ui.Context) void {
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    header(s, c);
    messages(s, c);
    composer(s, c);
}

fn header(s: *State, c: *ui.Context) void {
    const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(12).border(common.hx(common.border));
    ui.text(c, "团队频道", .{ .size = 15, .weight = .semibold, .color = common.hx(common.text) });
    if (s.pendingCount() > 0) {
        const pill = ui.div(c).row().itemsCenter().px(9).py(2).roundedFull().bg(common.hx(0x3a2c1c)).hover(common.hx(0x4a3624));
        ui.text(c, c.print("{d} 项待决定", .{s.pendingCount()}), .{ .size = 12, .color = common.hx(common.orange) });
        const clicked = pill.clicked();
        pill.end();
        if (clicked) s.page = .channel;
    }
    if (s.target) |ti| {
        if (ti < s.projects.items.len) {
            const target = ui.div(c).row().itemsCenter().gap(5).px(9).py(2).roundedFull().bg(common.hx(0x1c2b3a)).hover(common.hx(0x223448));
            ui.text(c, c.print("⌾ {s}", .{s.projects.items[ti].info.name}), .{ .size = 12, .color = common.hx(common.blue) });
            const clicked = target.clicked();
            target.end();
            if (clicked) s.page = .projects;
        } else {
            s.target = null;
        }
    }
    {
        const right = ui.div(c).row().grow().justifyEnd().itemsCenter().gap(6);
        const dot = ui.div(c).size(7, 7).circular().bg(common.hx(common.green));
        dot.end();
        ui.text(c, "实时", .{ .size = 12, .color = common.hx(common.muted) });
        right.end();
    }
    row.end();
}

fn messages(s: *State, c: *ui.Context) void {
    // Raw open (not the div builder) for `follow_end`: the stream keeps to
    // the newest message unless the owner scrolled up.
    _ = c.open(.{ .direction = .column, .width = .fill, .grow = 1, .scroll = true, .follow_end = true }, null);
    const col = ui.div(c).column().wFull().gap(18).p(18);
    // Index-based walk: choosing a decision option pushes messages from
    // inside the loop (choose → confirm), which may grow the list mid-frame.
    var i: usize = 0;
    while (i < s.messages.items.len) : (i += 1) {
        const m = s.messages.items[i];
        ui.keyInt(c, i);
        switch (m.kind) {
            .note => note(c, m),
            .owner => owner(c, m),
            .tool => toolRow(c, m),
            .diag => diagRow(c, m),
            .decision => decision(s, c, m),
        }
    }
    col.end();
    c.end();
}

/// An agent report: avatar, name and time, then the body.
pub fn note(c: *ui.Context, m: model.Message) void {
    const row = ui.div(c).row().wFull().gap(10);
    if (m.agent) |a| {
        common.avatar(c, a, 30);
    } else {
        const disc = ui.div(c).size(30, 30).circular().bg(common.hx(0x33363e));
        disc.end();
    }
    {
        const col = ui.div(c).column().grow().minW(0).gap(3);
        {
            const head = ui.div(c).row().itemsCenter().gap(8);
            ui.text(c, if (m.agent) |a| a.name else "团队", .{ .size = 13, .weight = .semibold, .color = common.hx(common.text) });
            ui.text(c, m.time, .{ .size = 11, .color = common.hx(common.faint), .tabular = true });
            head.end();
        }
        if (m.text.len > 0) {
            ui.text(c, m.text, .{ .size = 13.5, .color = common.hx(0xc9cbd2), .wrap = true, .leading = 1.4 });
        }
        col.end();
    }
    row.end();
}

/// The owner's reply, right-aligned on a raised bubble.
pub fn owner(c: *ui.Context, m: model.Message) void {
    const row = ui.div(c).row().wFull().justifyEnd();
    const bubble = ui.div(c).column().maxW(520).gap(3).px(13).py(9).rounded(12).bg(common.hx(0x2a2d35));
    ui.text(c, m.text, .{ .size = 13.5, .color = common.hx(common.text), .wrap = true, .leading = 1.4 });
    ui.text(c, m.time, .{ .size = 10.5, .color = common.hx(common.faint), .tabular = true });
    bubble.end();
    row.end();
}

/// A tool call the agent made: right-aligned, monospaced, dimmed.
pub fn toolRow(c: *ui.Context, m: model.Message) void {
    const row = ui.div(c).row().wFull().justifyEnd();
    const card = ui.div(c).column().maxW(560).px(11).py(7).rounded(8).bg(common.hx(0x1b1d22)).border(common.hx(common.border));
    ui.text(c, m.text, .{ .size = 12, .mono = true, .color = common.hx(common.muted), .wrap = true, .leading = 1.35 });
    card.end();
    row.end();
}

/// The command output fx streamed mid-turn: a full-width monospaced card.
pub fn diagRow(c: *ui.Context, m: model.Message) void {
    const card = ui.div(c).column().wFull().px(11).py(7).rounded(8).bg(common.hx(0x15171b)).border(common.hx(common.border));
    ui.text(c, m.text, .{ .size = 12, .mono = true, .color = common.hx(common.faint), .wrap = true, .leading = 1.3 });
    card.end();
}

/// A decision card with its options; the picked one shows once resolved.
fn decision(s: *State, c: *ui.Context, m: model.Message) void {
    const d = s.decisions.items[m.decision.?];
    const wrap = ui.div(c).column().wFull().gap(6);
    {
        const head = ui.div(c).row().itemsCenter().gap(10);
        if (m.agent) |a| {
            common.avatar(c, a, 30);
        } else {
            const disc = ui.div(c).size(30, 30).circular().bg(common.hx(0x33363e));
            disc.end();
        }
        {
            const who = ui.div(c).row().itemsCenter().gap(8);
            ui.text(c, if (m.agent) |a| a.name else "团队", .{ .size = 13, .weight = .semibold, .color = common.hx(common.text) });
            ui.text(c, m.time, .{ .size = 11, .color = common.hx(common.faint), .tabular = true });
            who.end();
        }
        head.end();
    }
    {
        const card = ui.div(c).column().wFull().gap(10).p(14).rounded(12).bg(common.hx(common.card)).border(common.hx(common.border));
        {
            const tag_row = ui.div(c).row().itemsCenter().gap(8);
            ui.text(c, "需要决定", .{ .size = 11, .weight = .semibold, .color = common.hx(common.orange) });
            ui.text(c, d.id, .{ .size = 11.5, .color = common.hx(common.faint), .tabular = true });
            tag_row.end();
        }
        ui.text(c, d.title, .{ .size = 14.5, .weight = .semibold, .color = common.hx(common.text), .wrap = true });
        ui.text(c, d.body, .{ .size = 13, .color = common.hx(0xb9bcc4), .wrap = true, .leading = 1.45 });
        for (d.options, 0..) |option, oi| {
            optionRow(s, c, m.decision.?, oi, option, d.choice);
        }
        if (d.choice != null) {
            ui.text(c, "已决定，任务已重新排队", .{ .size = 12, .color = common.hx(common.green) });
        }
        card.end();
    }
    wrap.end();
}

fn optionRow(s: *State, c: *ui.Context, di: usize, option: usize, o: model.Option, choice: ?usize) void {
    const picked = choice != null and choice.? == option;
    const dimmed = choice != null and choice.? != option;
    const base: ui.Color = if (picked) common.hx(0x233628) else common.hx(0x24272f);
    const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(11).py(8).rounded(8).bg(base).border(common.hx(if (picked) common.green else common.border)).hover(common.hx(0x2b2f38));
    ui.text(c, o.label, .{ .size = 13, .weight = .semibold, .color = common.hx(if (picked) common.green else common.orange), .tabular = true });
    {
        const col = ui.div(c).column().grow().minW(0);
        ui.text(c, o.detail, .{ .size = 13, .color = if (dimmed) common.hx(common.faint) else common.hx(0xc9cbd2), .wrap = true, .leading = 1.35 });
        col.end();
    }
    const clicked = !dimmed and choice == null and row.clicked();
    row.end();
    if (clicked) s.choose(di, option);
}

fn composer(s: *State, c: *ui.Context) void {
    const wrap = ui.div(c).column().wFull().p(14).border(common.hx(common.border));
    const box = ui.div(c).row().wFull().itemsCenter().gap(10).px(13).py(9).rounded(12).bg(common.hx(0x1b1d22)).border(common.hx(common.border)).hover(common.hx(0x1e2127));
    ui.text(c, "＋", .{ .size = 16, .color = common.hx(common.muted) });
    const placeholder = if (s.target != null and s.target.? < s.projects.items.len)
        c.print("给团队下指令（将在 {s} 中执行）…", .{s.projects.items[s.target.?].info.name})
    else
        "给团队下指令，例如：把 nsh 的 gallery 在 Linux 上截图检查一遍";
    const result = ui.textField(c, &s.input, .{
        .placeholder = placeholder,
        .width = .fill,
        .bare = true,
        .size = 13.5,
        .multiline = true,
        .max_lines = 5,
    });
    // Clicking the box's padding or its icon focuses the field, as a chat
    // composer does.
    if (box.clicked()) s.input.focus();
    const has_text = s.input.text().len > 0;
    {
        const send = ui.div(c).row().itemsCenter().gap(4).px(10).py(4).rounded(7).bg(common.hx(if (has_text) 0x2f6feb else 0x24272f));
        ui.text(c, "发送 ↑", .{ .size = 12, .weight = .medium, .color = common.hx(if (has_text) 0xffffff else common.faint) });
        const clicked = send.clicked();
        send.end();
        if (result.submitted or (clicked and has_text)) s.submit();
    }
    box.end();
    wrap.end();
}
