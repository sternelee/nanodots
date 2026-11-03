//! The agent settings page: the fx provider and model the embedded agent
//! uses, and custom provider definitions (base_url). Reads and writes the
//! same ~/.fx/settings.json as fx itself, through fx's settings store.
const std = @import("std");
const ui = @import("nanoui").ui;
const state_mod = @import("../state.zig");
const common = @import("common.zig");

const State = state_mod.State;

pub fn view(s: *State, c: *ui.Context) void {
    if (!s.settings_loaded) s.refreshSettings();
    const col = ui.div(c).column().sizeFull();
    defer col.end();
    header(s, c);
    const scroll = ui.div(c).column().wFull().grow().scrollY();
    const body = ui.div(c).column().wFull().gap(20).p(20);
    current(s, c);
    providerForm(s, c);
    customProviderForm(s, c);
    body.end();
    scroll.end();
}

fn header(s: *State, c: *ui.Context) void {
    const row = ui.div(c).row().wFull().itemsCenter().gap(10).px(18).py(11).border(common.hx(common.border));
    {
        const back = ui.div(c).row().itemsCenter().gap(6).px(7).py(3).rounded(6).hover(common.hx(common.card_hover));
        ui.text(c, "‹ 频道", .{ .size = 13, .color = common.hx(common.muted) });
        const clicked = back.clicked();
        back.end();
        if (clicked) s.page = .channel;
    }
    ui.text(c, "Agent 设置", .{ .size = 15, .weight = .semibold, .color = common.hx(common.text) });
    {
        const right = ui.div(c).row().grow().itemsCenter().justifyEnd();
        ui.text(c, "fx · ~/.fx/settings.json", .{ .size = 12, .color = common.hx(common.muted) });
        right.end();
    }
    row.end();
}

/// The read-only picture of what fx will use.
fn current(s: *State, c: *ui.Context) void {
    section(c, "当前");
    const card = ui.div(c).column().wFull().gap(6).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    for (s.settings_lines.items) |line| {
        ui.text(c, line, .{ .size = 13, .color = common.hx(0xc9cbd2), .wrap = true });
    }
    card.end();
}

fn providerForm(s: *State, c: *ui.Context) void {
    section(c, "提供商 / 模型");
    const card = ui.div(c).column().wFull().gap(10).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    field(c, "提供商", &s.set_provider, "gateway / codex / grok / 自定义 id，如 magpie");
    field(c, "模型", &s.set_model, "模型 id；留空则跟随提供商默认");
    saveButton(c, s, "保存");
    ui.text(c, "写入 ~/.fx/settings.json 的 provider 与 model，下一条指令生效；环境变量 FX_PROVIDER / FX_MODEL 优先于这里。", .{ .size = 12, .color = common.hx(common.faint), .wrap = true, .leading = 1.4 });
    card.end();
}

fn customProviderForm(s: *State, c: *ui.Context) void {
    section(c, "自定义提供商（base_url）");
    const card = ui.div(c).column().wFull().gap(10).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    field(c, "名称", &s.set_cp_name, "提供商 id，如 local、magpie");
    field(c, "base_url", &s.set_cp_url, "OpenAI 兼容端点，如 http://localhost:11434/v1");
    field(c, "凭证环境变量（可选）", &s.set_cp_env, "bearer token 所在的变量名；留空则无凭证");
    saveButton(c, s, "添加并选中");
    ui.text(c, "以 openai-chat-completions 协议接入任意端点，并写入 providers 定义。", .{ .size = 12, .color = common.hx(common.faint), .wrap = true });
    card.end();
}

fn section(c: *ui.Context, title: []const u8) void {
    ui.text(c, title, .{ .size = 12, .weight = .semibold, .color = common.hx(common.faint) });
}

fn field(c: *ui.Context, label: []const u8, buffer: *ui.TextBuffer, placeholder: []const u8) void {
    ui.text(c, label, .{ .size = 12, .color = common.hx(common.muted) });
    const box = ui.div(c).row().wFull().px(10).py(6).rounded(8).bg(common.hx(0x15171b)).border(common.hx(common.border));
    _ = ui.textField(c, buffer, .{ .width = .fill, .bare = true, .size = 13, .placeholder = placeholder });
    box.end();
}

fn saveButton(c: *ui.Context, s: *State, label: []const u8) void {
    const row = ui.div(c).row().wFull().itemsCenter().gap(10);
    {
        const button = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x2f6feb)).hover(common.hx(0x3a7dff));
        ui.text(c, label, .{ .size = 13, .weight = .medium, .color = .white });
        const clicked = button.clicked();
        button.end();
        if (clicked) {
            if (std.mem.eql(u8, label, "保存")) {
                s.saveProviderModel();
            } else {
                s.saveCustomProvider();
            }
        }
    }
    const is_provider_form = std.mem.eql(u8, label, "保存");
    const note_text: []const u8 = if (is_provider_form) s.set_note else s.set_cp_note;
    const note_err = if (is_provider_form) s.set_note_err else s.set_cp_note_err;
    if (note_text.len > 0) {
        ui.text(c, note_text, .{ .size = 12, .color = common.hx(if (note_err) common.red else common.green) });
    }
    row.end();
}