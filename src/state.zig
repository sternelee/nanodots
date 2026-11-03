//! App state: the seeded workspace, navigation, the composer, and applying
//! fx agent events to the channel. Everything the views read and mutate.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const model = @import("model.zig");
const seed = @import("seed.zig");
const agent = @import("agent.zig");

const alloc = model.alloc;

pub const Page = union(enum) {
    channel,
    task: usize,
    machine: usize,
    settings,
    projects,
    project: usize,
    session: usize,
};

/// One added project: its directory, the agent runtime bound to it, and an
/// interactive multi-turn session thread, like fx cli in that directory.
pub const ProjectEntry = struct {
    info: model.Project,
    runtime: *agent.Runtime,
    app: *State,
    thread: std.ArrayList(model.Message) = .empty,
    input: ui.TextBuffer = .{},
    /// Live turn's streaming message, diagnostics collector and task, if any.
    streaming: i32 = -1,
    diag: i32 = -1,
    turn_task: i32 = -1,

    fn deinit(entry: *ProjectEntry) void {
        entry.runtime.deinit();
        entry.input.deinit();
        for (entry.thread.items) |m| {
            if (m.text.len > 0) alloc.free(m.text);
        }
        entry.thread.deinit(alloc);
        alloc.free(entry.info.name);
        alloc.free(entry.info.path);
        alloc.destroy(entry);
    }
};

pub const State = struct {
    window: ?*nanoui.Window = null,
    page: Page = .channel,

    decisions: std.ArrayList(model.Decision) = .empty,
    tasks: std.ArrayList(model.Task) = .empty,
    machines: std.ArrayList(model.Machine) = .empty,
    messages: std.ArrayList(model.Message) = .empty,

    input: ui.TextBuffer = .{},
    /// The agent turn a composer instruction opened; -1 when none.
    turn_task: i32 = -1,
    /// The runtime and project the live turn runs on.
    turn_runtime: ?*agent.Runtime = null,
    turn_project: ?usize = null,
    /// Index into messages of the reply currently streaming, if any.
    streaming: i32 = -1,
    /// Index of the message collecting streamed diagnostics, if any.
    diag: i32 = -1,
    runtime: ?*agent.Runtime = null,
    cwd: []u8 = "",

    /// Workspaces the owner added, each with its own fx session.
    projects: std.ArrayList(*ProjectEntry) = .empty,
    /// Where composer instructions go: a project's directory, or null for
    /// the launch directory.
    target: ?usize = null,
    add_path: ui.TextBuffer = .{},
    add_note: []u8 = &.{},
    add_note_err: bool = false,

    /// The agent settings page: editable buffers and what it shows.
    set_provider: ui.TextBuffer = .{},
    set_model: ui.TextBuffer = .{},
    set_cp_name: ui.TextBuffer = .{},
    set_cp_url: ui.TextBuffer = .{},
    set_cp_env: ui.TextBuffer = .{},
    settings_lines: std.ArrayList([]u8) = .empty,
    set_note: []u8 = &.{},
    set_note_err: bool = false,
    set_cp_note: []u8 = &.{},
    set_cp_note_err: bool = false,
    settings_loaded: bool = false,

    pub fn create() !*State {
        const self = try alloc.create(State);
        self.* = .{};
        self.cwd = try @import("fx").shared_io.realpathAlloc(alloc, ".");
        self.runtime = try agent.Runtime.create(self.cwd);
        self.runtime.?.setCallback(self, onAgentEvent);

        const now_ms = @import("fx").shared_io.milliTimestamp();
        for (seed.decisions) |d| try self.decisions.append(alloc, d);
        for (seed.tasks) |t| {
            var task = t;
            task.started_at_ms = now_ms - t.started_min_ago * 60_000;
            try self.tasks.append(alloc, task);
        }
        for (seed.machines) |m| try self.machines.append(alloc, m);
        for (seed.messages) |m| {
            try self.messages.append(alloc, .{
                .agent = if (m.agent) |a| a.* else null,
                .time = m.time,
                .kind = if (m.decision != null) .decision else if (m.owner.len > 0) .owner else .note,
                .text = if (m.owner.len > 0) m.owner else m.text,
                .decision = m.decision,
            });
        }
        return self;
    }

    pub fn destroy(self: *State) void {
        if (self.runtime) |runtime| runtime.deinit();
        for (self.projects.items) |entry| entry.deinit();
        self.projects.deinit(alloc);
        self.add_path.deinit();
        if (self.add_note.len > 0) alloc.free(self.add_note);
        self.input.deinit();
        self.set_provider.deinit();
        self.set_model.deinit();
        self.set_cp_name.deinit();
        self.set_cp_url.deinit();
        self.set_cp_env.deinit();
        for (self.settings_lines.items) |line| alloc.free(line);
        self.settings_lines.deinit(alloc);
        if (self.set_note.len > 0) alloc.free(self.set_note);
        if (self.set_cp_note.len > 0) alloc.free(self.set_cp_note);
        alloc.free(self.cwd);
        self.decisions.deinit(alloc);
        self.tasks.deinit(alloc);
        self.machines.deinit(alloc);
        self.messages.deinit(alloc);
        alloc.destroy(self);
    }

    pub fn pendingCount(self: *State) usize {
        var n: usize = 0;
        for (self.decisions.items) |d| {
            if (d.choice == null) n += 1;
        }
        return n;
    }

    pub fn runningCount(self: *State) usize {
        var n: usize = 0;
        for (self.tasks.items) |t| {
            if (t.status == .running) n += 1;
        }
        return n;
    }

    /// Live elapsed minutes for a task since its start timestamp.
    pub fn minutesAgo(_: *State, since_ms: i64) i64 {
        const now_ms = @import("fx").shared_io.milliTimestamp();
        return @max(0, @divFloor(now_ms - since_ms, 60_000));
    }

    /// How long a task has run: live for running tasks, the seed value
    /// for finished ones.
    pub fn elapsedMinutes(s: *State, task: usize) i64 {
        const t = s.tasks.items[task];
        return if (t.status == .running) s.minutesAgo(t.started_at_ms) else t.started_min_ago;
    }

    /// The runtime instructions should run on: the target project's, or the
    /// launch directory's.
    pub fn targetRuntime(s: *State) struct { runtime: *agent.Runtime, label: []const u8, project: ?usize } {
        if (s.target) |ti| {
            if (ti < s.projects.items.len) {
                const entry = s.projects.items[ti];
                return .{ .runtime = entry.runtime, .label = entry.info.name, .project = ti };
            }
            s.target = null;
        }
        return .{ .runtime = s.runtime.?, .label = "本机", .project = null };
    }

    /// Validates the path field, normalizes it and binds a new fx runtime.
    pub fn addProject(s: *State) void {
        const engine = @import("fx");
        const typed = std.mem.trimEnd(u8, s.add_path.text(), " \n\t");
        if (typed.len == 0) {
            s.addNote("先输入项目目录", true);
            return;
        }
        const io = engine.shared_io.getIo();
        const real = engine.shared_io.realpathAlloc(alloc, typed) catch {
            s.addNote("目录不存在或无法访问", true);
            return;
        };
        var dir = std.Io.Dir.openDirAbsolute(io, real, .{}) catch {
            alloc.free(real);
            s.addNote("不是目录", true);
            return;
        };
        dir.close(io);
        for (s.projects.items) |entry| {
            if (std.mem.eql(u8, entry.info.path, real)) {
                alloc.free(real);
                s.addNote("项目已存在", true);
                return;
            }
        }
        const name = alloc.dupe(u8, std.Io.Dir.path.basename(real)) catch {
            alloc.free(real);
            return;
        };
        const runtime = agent.Runtime.create(real) catch {
            alloc.free(name);
            alloc.free(real);
            s.addNote("fx runtime 创建失败", true);
            return;
        };
        const entry = alloc.create(ProjectEntry) catch {
            runtime.deinit();
            alloc.free(name);
            alloc.free(real);
            s.addNote("添加失败", true);
            return;
        };
        entry.* = .{ .info = .{ .name = name, .path = real, .added_ms = engine.shared_io.milliTimestamp() }, .runtime = runtime, .app = s };
        // Events from this runtime route to the session thread, not the channel.
        runtime.setCallback(entry, onSessionEvent);
        s.projects.append(alloc, entry) catch {
            entry.deinit();
            s.addNote("添加失败", true);
            return;
        };
        s.add_path.clear();
        s.target = s.projects.items.len - 1;
        s.addNote("项目已添加并设为目标", false);
    }

    /// Drops a project, its runtime, its session thread and target pointers.
    pub fn removeProject(s: *State, index: usize) void {
        if (index >= s.projects.items.len) return;
        const entry = s.projects.orderedRemove(index);
        entry.deinit();
        if (s.target) |ti| {
            if (ti == index) {
                s.target = null;
            } else if (ti > index) {
                s.target = ti - 1;
            }
        }
        switch (s.page) {
            .project, .session => |pi| if (pi == index) {
                s.page = .projects;
            },
            else => {},
        }
    }

    fn addNote(s: *State, text: []const u8, fail: bool) void {
        if (s.add_note.len > 0) alloc.free(s.add_note);
        s.add_note = alloc.dupe(u8, text) catch &.{};
        s.add_note_err = fail;
        if (s.window) |window| window.redraw();
    }

    /// Cancel the agent turn `index` belongs to, if it is the live one.
    pub fn cancelTask(s: *State, index: usize) void {
        if (s.turn_task != index) return;
        if (s.turn_runtime) |runtime| runtime.cancel() else if (s.runtime) |runtime| runtime.cancel();
        if (index < s.tasks.items.len) {
            s.tasks.items[index].status = .cancelled;
        }
        s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = "收到：取消该任务 — fx 回合已中止" });
        s.streaming = -1;
        s.diag = -1;
        s.turn_task = -1;
        s.turn_runtime = null;
    }

    /// Rereads ~/.fx/settings.json into the settings page (lines and the
    /// editable buffers' prefills). Called on first open and after a save.
    pub fn refreshSettings(s: *State) void {
        for (s.settings_lines.items) |line| alloc.free(line);
        s.settings_lines.clearRetainingCapacity();
        const engine = @import("fx");
        const push = struct {
            fn line(st: *State, comptime fmt: []const u8, args: anytype) void {
                const text = alloc.print(fmt, args) catch return;
                st.settings_lines.append(alloc, text) catch alloc.free(text);
            }
        }.line;

        const home = engine.shared_io.homeDir() orelse {
            push(s, "找不到 HOME，无法读取 fx 配置", .{});
            return;
        };
        const path = alloc.print("{s}/.fx/settings.json", .{home}) catch return;
        const data = readFile(path) orelse {
            push(s, "（还没有 {s}）", .{path});
            s.settings_loaded = true;
            return;
        };
        var parsed = std.json.parseFromSlice(std.json.Value, alloc, data, .{}) catch {
            push(s, "settings.json 解析失败", .{});
            return;
        };
        defer parsed.deinit();
        if (parsed.value != .object) {
            push(s, "settings.json 不是对象", .{});
            return;
        }
        const root = parsed.value.object;

        var provider: []const u8 = "（未设置，跟随 fx 默认）";
        if (root.get("provider")) |v| {
            if (v == .string) provider = v.string;
        }
        push(s, "提供商：{s}", .{provider});
        var model_id: ?[]const u8 = null;
        // New-style: per-provider entries in the "models" map. Legacy: a
        // top-level "model" ("provider/model"), "codex_model", "grok_model".
        if (root.get("models")) |v| {
            if (v == .object) {
                if (v.object.get(provider)) |m| {
                    if (m == .string) model_id = m.string;
                }
            }
        }
        if (model_id == null) {
            const legacy_key: []const u8 = if (std.mem.eql(u8, provider, "codex"))
                "codex_model"
            else if (std.mem.eql(u8, provider, "grok"))
                "grok_model"
            else
                "model";
            if (root.get(legacy_key)) |v| {
                if (v == .string) {
                    var id = v.string;
                    const prefix = alloc.print("{s}/", .{provider}) catch "/";
                    if (std.mem.startsWith(u8, id, prefix)) id = id[prefix.len..];
                    model_id = id;
                }
            }
        }
        if (model_id) |id| {
            push(s, "模型：{s}", .{id});
            s.set_model.set(id);
        } else {
            push(s, "模型：（跟随提供商默认）", .{});
        }
        if (engine.shared_io.getenv("FX_PROVIDER")) |v| {
            push(s, "环境变量 FX_PROVIDER={s}（优先生效）", .{v});
        }
        if (engine.shared_io.getenv("FX_MODEL")) |v| {
            push(s, "环境变量 FX_MODEL={s}（优先生效）", .{v});
        }
        if (root.get("providers")) |v| {
            if (v == .object) {
                var it = v.object.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* != .object) continue;
                    const def = entry.value_ptr.*.object;
                    var url: []const u8 = "（无 base_url）";
                    if (def.get("base_url")) |u| {
                        if (u == .string) url = u.string;
                    }
                    var auth: []const u8 = "无凭证";
                    if (def.get("auth")) |a| {
                        if (a == .object) {
                            if (a.object.get("type")) |t| {
                                if (t == .string and std.mem.eql(u8, t.string, "bearer")) {
                                    if (a.object.get("env")) |e| {
                                        if (e == .string) {
                                            auth = alloc.print("环境变量 {s}", .{e.string}) catch "环境变量";
                                            if (std.mem.eql(u8, entry.key_ptr.*, provider)) s.set_cp_env.set(e.string);
                                        }
                                    } else {
                                        auth = "bearer";
                                    }
                                }
                            }
                        }
                    }
                    push(s, "自定义提供商 {s}：{s}（凭证：{s}）", .{ entry.key_ptr.*, url, auth });
                }
            }
        }
        s.set_provider.set(provider);
        s.set_cp_name.set(if (std.mem.eql(u8, provider, "gateway") or std.mem.eql(u8, provider, "codex") or std.mem.eql(u8, provider, "grok")) "" else provider);
        s.settings_loaded = true;
    }

    /// Saves the provider (and optional model) text fields through fx's
    /// settings store; takes effect on the next agent turn.
    pub fn saveProviderModel(s: *State) void {
        const engine = @import("fx");
        const provider_text = s.set_provider.text();
        const pid = engine.model_provider.parse(provider_text) orelse {
            s.note(false, "无法识别的提供商 id（字母数字和 - _ .）", true);
            return;
        };
        var patch = engine.provider_settings.UserSettingsPatch{ .provider = pid };
        const model_id = s.set_model.text();
        if (model_id.len > 0) {
            patch.model_preference = .{ .provider = pid, .model = alloc.dupe(u8, model_id) catch return };
        }
        s.commitPatch(patch, "提供商已保存，下一条指令生效", false);
    }

    /// Adds or updates a custom provider definition (base_url) and selects
    /// it, in the manner of `fx /provider` upserts.
    pub fn saveCustomProvider(s: *State) void {
        const engine = @import("fx");
        const name = s.set_cp_name.text();
        const url = s.set_cp_url.text();
        if (name.len == 0 or url.len == 0) {
            s.note(false, "名称和 base_url 都必填", true);
            return;
        }
        const env = s.set_cp_env.text();
        const pid = engine.model_provider.parse(name) orelse {
            s.note(false, "无法识别的提供商 id（字母数字和 - _ .）", true);
            return;
        };
        s.commitPatch(.{
            .provider = pid,
            .provider_definition = .{ .upsert = .{
                .id = alloc.dupe(u8, name) catch return,
                .base_url = alloc.dupe(u8, url) catch return,
                .bearer_env = if (env.len > 0) alloc.dupe(u8, env) catch return else null,
            } },
        }, "自定义提供商已保存并选中，下一条指令生效", true);
    }

    fn commitPatch(s: *State, patch: @import("fx").provider_settings.UserSettingsPatch, ok_message: []const u8, cp: bool) void {
        const engine = @import("fx");
        const home = engine.shared_io.homeDir() orelse {
            s.note(cp, "找不到 HOME，无法写入 fx 配置", true);
            return;
        };
        var outcome = engine.provider_settings.setUserPreferencesAtHome(alloc, home, patch) catch |err| {
            s.note(cp, @errorName(err), true);
            return;
        };
        defer outcome.deinit(alloc);
        s.note(cp, ok_message, false);
        s.refreshSettings();
    }

    fn note(s: *State, cp: bool, text: []const u8, fail: bool) void {
        if (cp) {
            if (s.set_cp_note.len > 0) alloc.free(s.set_cp_note);
            s.set_cp_note = alloc.dupe(u8, text) catch &.{};
            s.set_cp_note_err = fail;
        } else {
            if (s.set_note.len > 0) alloc.free(s.set_note);
            s.set_note = alloc.dupe(u8, text) catch &.{};
            s.set_note_err = fail;
        }
        if (s.window) |window| window.redraw();
    }

    pub fn view(s: *State, c: *ui.Context) void {
        @import("ui/root.zig").view(s, c);
    }

    /// Resolve a decision: record the choice, echo the owner's reply into
    /// the channel, and have hub confirm it.
    pub fn choose(s: *State, decision: usize, option: usize) void {
        const d = &s.decisions.items[decision];
        if (d.choice != null or option >= d.options.len) return;
        d.choice = option;
        const picked = d.options[option];
        const owner_line = alloc.print("{s}（{s}）", .{ d.outcome, d.id }) catch return;
        s.pushMessage(.{ .agent = null, .time = now(), .kind = .owner, .text = owner_line });
        const confirm = alloc.print("收到 {s}：{s} — {s}", .{ d.id, picked.detail, d.outcome }) catch return;
        s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = confirm });
    }

    /// The composer submitted an instruction for the team; it runs in the
    /// target project's directory (or the launch directory).
    pub fn submit(s: *State) void {
        const text = s.input.text();
        if (text.len == 0) return;
        const owned = alloc.dupe(u8, text) catch return;
        defer alloc.free(owned);
        s.input.clear();
        s.pushMessage(.{ .agent = null, .time = now(), .kind = .owner, .text = owned });

        const dest = s.targetRuntime();
        const runtime = dest.runtime;
        if (runtime.busy()) {
            const line = alloc.print("团队在忙上一个任务，先把这条排队：{s}", .{shorten(owned)}) catch return;
            s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = line });
        }
        runtime.start(owned) catch {
            s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = "fx agent 启动失败" });
            return;
        };
        s.turn_task = @intCast(s.tasks.items.len);
        s.turn_runtime = runtime;
        s.turn_project = dest.project;
        const title = alloc.print("hub: {s}", .{shorten(owned)}) catch return;
        s.tasks.append(alloc, .{
            .id = "T-0107",
            .title = title,
            .role = "hub",
            .host = alloc.dupe(u8, dest.label) catch "",
            .model = "fx",
            .status = .running,
            .started_min_ago = 0,
            .started_at_ms = @import("fx").shared_io.milliTimestamp(),
            .project = dest.project,
            .request = alloc.dupe(u8, owned) catch "",
        }) catch {};
        s.streaming = @intCast(s.messages.items.len);
        s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = "" });
    }

    fn pushMessage(s: *State, message: model.Message) void {
        s.messages.append(alloc, message) catch return;
        if (s.window) |window| window.redraw();
    }

    /// One turn of the project's interactive session: the input becomes an
    /// owner message, the runtime answers into the thread (fx keeps the
    /// session's context across turns, as the cli does).
    pub fn sessionSubmit(s: *State, entry: *ProjectEntry) void {
        _ = s;
        const text = entry.input.text();
        if (text.len == 0) return;
        const owned = alloc.dupe(u8, text) catch return;
        defer alloc.free(owned);
        entry.input.clear();
        entry.thread.append(alloc, .{ .agent = null, .time = now(), .kind = .owner, .text = alloc.dupe(u8, owned) catch return }) catch return;
        if (entry.runtime.busy()) {
            entry.thread.append(alloc, .{ .agent = seed.hub, .time = now(), .kind = .note, .text = "上一个回合还在运行，等它结束再发" }) catch {};
        }
        entry.runtime.start(owned) catch {
            entry.thread.append(alloc, .{ .agent = seed.hub, .time = now(), .kind = .note, .text = "fx agent 启动失败" }) catch {};
            return;
        };
        entry.streaming = @intCast(entry.thread.items.len);
        entry.thread.append(alloc, .{ .agent = seed.hub, .time = now(), .kind = .note, .text = "" }) catch {};
        if (entry.app.window) |window| window.redraw();
    }

    /// fx events from a project runtime land here (the callback's context is
    /// the ProjectEntry), appending to its session thread.
    fn onSessionEvent(context: ?*anyopaque, event: agent.Event) void {
        const entry: *ProjectEntry = @ptrCast(@alignCast(context.?));
        switch (event) {
            .text => |bytes| {
                entry.diag = -1;
                if (entry.streaming >= 0) {
                    const message = &entry.thread.items[@intCast(entry.streaming)];
                    const grown = alloc.alloc(u8, message.text.len + bytes.len) catch return;
                    @memcpy(grown[0..message.text.len], message.text);
                    @memcpy(grown[message.text.len..], bytes);
                    message.text = grown;
                }
            },
            .diagnostic => |bytes| {
                if (std.mem.startsWith(u8, bytes, "Running ")) return;
                if (entry.diag >= 0 and entry.diag < entry.thread.items.len) {
                    const message = &entry.thread.items[@intCast(entry.diag)];
                    const grown = alloc.alloc(u8, message.text.len + 1 + bytes.len) catch return;
                    @memcpy(grown[0..message.text.len], message.text);
                    grown[message.text.len] = '\n';
                    @memcpy(grown[message.text.len + 1 ..], bytes);
                    message.text = grown;
                } else {
                    entry.thread.append(alloc, .{ .agent = seed.hub, .time = now(), .kind = .diag, .text = alloc.dupe(u8, bytes) catch return }) catch return;
                    entry.diag = @intCast(entry.thread.items.len - 1);
                }
            },
            .tool => |call| {
                entry.diag = -1;
                var output: []const u8 = std.mem.trimEnd(u8, call.output, "\n");
                if (output.len > 240) output = output[0..240];
                const line = if (output.len > 0)
                    alloc.print("{s} · {s}\n{s}", .{ call.name, call.status, output }) catch return
                else
                    alloc.print("{s} · {s}", .{ call.name, call.status }) catch return;
                entry.thread.append(alloc, .{ .agent = seed.hub, .time = now(), .kind = .tool, .text = line }) catch {};
            },
            .done => {
                entry.diag = -1;
                entry.streaming = -1;
            },
            .failed => |bytes| {
                entry.diag = -1;
                entry.streaming = -1;
                const line = alloc.print("fx agent 失败：{s}", .{bytes}) catch return;
                entry.thread.append(alloc, .{ .agent = seed.hub, .time = now(), .kind = .note, .text = line }) catch {};
            },
        }
        if (entry.app.window) |window| window.redraw();
    }

    /// fx runtime events arrive on the UI thread through this.
    fn onAgentEvent(context: ?*anyopaque, event: agent.Event) void {
        const s: *State = @ptrCast(@alignCast(context.?));
        switch (event) {
            .text => |bytes| {
                s.diag = -1;
                if (s.streaming >= 0) {
                    const message = &s.messages.items[@intCast(s.streaming)];
                    const grown = alloc.alloc(u8, message.text.len + bytes.len) catch return;
                    @memcpy(grown[0..message.text.len], message.text);
                    @memcpy(grown[message.text.len..], bytes);
                    message.text = grown;
                }
            },
            .diagnostic => |bytes| {
                // fx's raw mode echoes each tool call as "Running …" on
                // stderr; the structured .tool event shows those already.
                if (std.mem.startsWith(u8, bytes, "Running ")) return;
                // The rest (a shell's output lines) collect into one
                // monospaced card instead of a message per line.
                if (s.diag >= 0 and s.diag < s.messages.items.len) {
                    const message = &s.messages.items[@intCast(s.diag)];
                    const grown = alloc.alloc(u8, message.text.len + 1 + bytes.len) catch return;
                    @memcpy(grown[0..message.text.len], message.text);
                    grown[message.text.len] = '\n';
                    @memcpy(grown[message.text.len + 1 ..], bytes);
                    message.text = grown;
                } else {
                    s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .diag, .text = bytes });
                    s.diag = @intCast(s.messages.items.len - 1);
                }
            },
            .tool => |call| {
                s.diag = -1;
                var output: []const u8 = std.mem.trimEnd(u8, call.output, "\n");
                if (output.len > 240) output = output[0..240];
                const line = if (output.len > 0)
                    alloc.print("{s} · {s}\n{s}", .{ call.name, call.status, output }) catch return
                else
                    alloc.print("{s} · {s}", .{ call.name, call.status }) catch return;
                s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .tool, .text = line });
            },
            .done => |done| {
                s.diag = -1;
                if (s.turn_task >= 0) {
                    if (s.turn_task < s.tasks.items.len) {
                        s.tasks.items[@intCast(s.turn_task)].status = .done;
                    }
                    const line = alloc.print("任务完成（{s}，session {s}）", .{ if (done.model.len > 0) done.model else "fx", if (done.session_id.len > 0) done.session_id else "-" }) catch return;
                    s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = line });
                    s.streaming = -1;
                    s.turn_task = -1;
                    s.turn_runtime = null;
                    s.turn_project = null;
                }
            },
            .failed => |bytes| {
                s.diag = -1;
                if (s.turn_task >= 0) {
                    if (s.turn_task < s.tasks.items.len) {
                        s.tasks.items[@intCast(s.turn_task)].status = .failed;
                    }
                    const line = alloc.print("fx agent 失败：{s}", .{bytes}) catch return;
                    s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = line });
                    s.streaming = -1;
                    s.turn_task = -1;
                    s.turn_runtime = null;
                    s.turn_project = null;
                }
            },
        }
        if (s.window) |window| window.redraw();
    }
};

fn shorten(text: []const u8) []const u8 {
    const limit = 64;
    if (text.len <= limit) return text;
    return text[0..limit];
}

/// Reads a file fully, or null on any failure. Caller frees the result.
fn readFile(path: []const u8) ?[]u8 {
    const engine = @import("fx");
    const io = engine.shared_io.getIo();
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);
    return engine.shared_io.readFileToEnd(alloc, &file, 1 << 20) catch null;
}

var clock_buf: [8]u8 = undefined;

fn now() []const u8 {
    const millis = @import("fx").shared_io.milliTimestamp();
    const secs: u64 = @intCast(@divFloor(millis, 1000));
    const hh = (secs / 3600 + 8) % 24; // demo clock, fixed to UTC+8
    const mm = (secs / 60) % 60;
    return std.mem.print(&clock_buf, "{d:0>2}:{d:0>2}", .{ hh, mm }) catch "??:??";
}
