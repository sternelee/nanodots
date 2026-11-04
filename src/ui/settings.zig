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
    webhookSection(s, c);
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

/// GitHub webhook: the inbound half of the watches. GitHub pushes events
/// to the app's local receiver; a delivery wakes the matching watcher
/// within ~1s while polling stays as the safety net.
fn webhookSection(s: *State, c: *ui.Context) void {
    section(c, "GitHub webhook");
    const card = ui.div(c).column().wFull().gap(10).p(13).rounded(10).bg(common.hx(common.card)).border(common.hx(common.border));
    {
        const row = ui.div(c).row().wFull().itemsCenter().gap(8);
        const toggle = ui.div(c).row().itemsCenter().px(9).py(3).rounded(6).bg(common.hx(if (s.wh_enabled) 0x1c2b3a else 0x24272f)).hover(common.hx(common.card_hover));
        ui.text(c, if (s.wh_enabled) "已启用" else "已停用", .{ .size = 12, .weight = if (s.wh_enabled) .medium else .regular, .color = common.hx(if (s.wh_enabled) common.blue else common.faint) });
        const t_clicked = toggle.clicked();
        toggle.end();
        if (t_clicked) s.toggleWebhook();
        {
            const port_box = ui.div(c).row().w(110).px(10).py(5).rounded(8).bg(common.hx(0x15171b)).border(common.hx(common.border));
            const result = ui.textField(c, &s.wh_port_buf, .{ .width = .fill, .bare = true, .size = 13, .placeholder = "端口" });
            port_box.end();
            if (result.submitted) s.saveWebhookFromForm();
        }
        const save = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x2f6feb)).hover(common.hx(0x3a7dff));
        ui.text(c, "保存并应用", .{ .size = 13, .weight = .medium, .color = .white });
        const s_clicked = save.clicked();
        save.end();
        if (s_clicked) s.saveWebhookFromForm();
        {
            const status = ui.div(c).row().grow().itemsCenter().justifyEnd().gap(6);
            const running = s.webhook != null;
            const dot = ui.div(c).size(7, 7).circular().bg(common.hx(if (running) common.green else common.faint));
            dot.end();
            ui.text(c, if (running) c.print("运行中 · 127.0.0.1:{d}", .{s.wh_port}) else "未运行", .{ .size = 12, .color = common.hx(if (running) common.muted else common.faint) });
            status.end();
        }
        row.end();
    }
    if (s.wh_note.len > 0) {
        ui.text(c, s.wh_note, .{ .size = 12, .color = common.hx(if (s.wh_note_err) common.red else common.green) });
    }
    ui.text(c, "Hook URL（在下方框内全选复制，粘贴到 GitHub 仓库的 Webhook Payload URL）", .{ .size = 12, .color = common.hx(common.muted) });
    {
        const box = ui.div(c).row().wFull().px(10).py(6).rounded(8).bg(common.hx(0x15171b)).border(common.hx(common.border));
        _ = ui.textField(c, &s.wh_url_buf, .{ .width = .fill, .bare = true, .size = 12.5 });
        box.end();
    }
    field(c, "Secret（可选，用于验签 X-Hub-Signature-256）", &s.wh_secret_buf, "与 GitHub webhook 的 Secret 一致；留空则不验签");
    {
        const save = ui.div(c).row().itemsCenter().px(12).py(5).rounded(7).bg(common.hx(0x24272f)).hover(common.hx(0x2b2f38));
        ui.text(c, "保存 Secret", .{ .size = 12.5, .weight = .medium, .color = common.hx(common.muted) });
        const clicked = save.clicked();
        save.end();
        if (clicked) s.saveWebhookFromForm();
    }
    ui.text(c, "配置流程：GitHub 仓库 → Settings → Webhooks → Add webhook。Payload URL 填上面的地址（本机地址 GitHub 无法直达，需先用 smee.io 或 ngrok 暴露到公网，如 smee 的 Forward to 填这里）；Content type 选 application/json；Secret 填上面的值；触发事件勾 Pull requests 与 Issues。添加后 GitHub 会发送 ping，收到即说明连通。", .{ .size = 12, .color = common.hx(common.faint), .wrap = true, .leading = 1.45 });
    ui.text(c, "收到 push 事件会立即唤醒对应仓库的监听（约 1 秒内开始检查），轮询仍按原间隔兜底。事件记录（最新在前）：", .{ .size = 12, .color = common.hx(common.faint), .wrap = true, .leading = 1.45 });
    if (s.wh_events.items.len == 0) {
        ui.text(c, "（还没有收到过事件）", .{ .size = 12, .color = common.hx(common.faint) });
    }
    const list = ui.div(c).column().wFull().gap(4);
    var k: usize = 0;
    while (k < s.wh_events.items.len) : (k += 1) {
        const e = s.wh_events.items[s.wh_events.items.len - 1 - k];
        const row = ui.div(c).row().wFull().itemsCenter().gap(8);
        ui.text(c, if (e.verified) "✓" else "✗", .{ .size = 12, .color = common.hx(if (e.verified) common.green else common.red) });
        const what = if (e.reject.len > 0)
            c.print("{s} {s} — {s}", .{ e.kind, e.action, e.reject })
        else if (e.number > 0)
            c.print("{s} {s} {s} #{d}", .{ e.kind, e.action, e.repo, e.number })
        else
            c.print("{s} {s} {s}", .{ e.kind, e.action, e.repo });
        {
            const mid = ui.div(c).row().grow().minW(0);
            ui.text(c, what, .{ .size = 12, .color = common.hx(common.muted), .truncate = .ellipsis });
            mid.end();
        }
        if (e.title.len > 0) {
            const t = ui.div(c).row().justifyEnd();
            ui.text(c, e.title, .{ .size = 12, .color = common.hx(common.faint), .truncate = .ellipsis });
            t.end();
        }
        row.end();
    }
    list.end();
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