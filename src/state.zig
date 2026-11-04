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
    watchers,
    watch: usize,
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

/// One watched GitHub repo: its own fx runtime/session, a polling schedule
/// and the transcript of its checks. Findings are pushed to the team
/// channel, quiet checks only update the status.
pub const WatchEntry = struct {
    info: model.Watch,
    runtime: *agent.Runtime,
    app: *State,
    thread: std.ArrayList(model.Message) = .empty,
    streaming: i32 = -1,
    diag: i32 = -1,
    /// The task the running check belongs to, if any.
    turn_task: i32 = -1,
    enabled: bool = true,
    checks: u32 = 0,
    findings: u32 = 0,
    last_check_ms: i64 = 0,
    next_fire_ms: i64 = 0,
    /// Short version of the last reply, fed into the next instruction.
    last_result: []u8 = &.{},
    /// Numbers the owner dismissed; never reported again.
    ignored: std.ArrayList(u32) = .empty,
    /// Everything already reported (findings and baseline items); the check
    /// instruction lists these so restarts diff against them, not just the
    /// fx session's memory.
    reported: std.ArrayList(u32) = .empty,

    fn deinit(entry: *WatchEntry) void {
        entry.runtime.deinit();
        for (entry.thread.items) |m| {
            if (m.text.len > 0) alloc.free(m.text);
        }
        entry.thread.deinit(alloc);
        entry.ignored.deinit(alloc);
        entry.reported.deinit(alloc);
        if (entry.last_result.len > 0) alloc.free(entry.last_result);
        alloc.free(entry.info.repo);
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

    /// GitHub repos watched for new PRs/issues, each polling on a schedule.
    watchers: std.ArrayList(*WatchEntry) = .empty,
    /// The add-watch form: repo field, target toggles and interval preset.
    watch_repo: ui.TextBuffer = .{},
    watch_prs: bool = true,
    watch_issues: bool = false,
    watch_interval_min: u32 = 15,
    watch_note: []u8 = &.{},
    watch_note_err: bool = false,
    /// Running id sequence for watcher check tasks (W-0001, …).
    watch_seq: u32 = 0,
    /// Id sequences past the seed data: decisions D-0011…, tasks T-0110….
    decision_seq: u32 = 10,
    task_seq: u32 = 110,
    /// Whether the 1s scheduler pump has been armed (from the first frame).
    tick_armed: bool = false,

    /// GitHub webhook receiver (the settings page configures it). Inbound
    /// deliveries wake matching watchers immediately; polling stays as the
    /// safety net.
    webhook: ?*@import("webhook.zig").Server = null,
    wh_enabled: bool = false,
    wh_port: u16 = 9781,
    wh_port_buf: ui.TextBuffer = .{},
    wh_secret_buf: ui.TextBuffer = .{},
    wh_secret: []u8 = &.{},
    wh_token: []u8 = &.{},
    /// Derived hook URL, shown in a copyable field on the settings page.
    wh_url_buf: ui.TextBuffer = .{},
    /// Newest-last log of received deliveries, capped at 20.
    wh_events: std.ArrayList(@import("webhook.zig").Event) = .empty,
    wh_note: []u8 = &.{},
    wh_note_err: bool = false,

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
        self.loadWatchers();
        self.loadWebhook();
        return self;
    }

    pub fn destroy(self: *State) void {
        if (self.runtime) |runtime| runtime.deinit();
        for (self.projects.items) |entry| entry.deinit();
        self.projects.deinit(alloc);
        for (self.watchers.items) |entry| entry.deinit();
        self.watchers.deinit(alloc);
        if (self.webhook) |server| server.stop();
        for (self.wh_events.items) |e| @import("webhook.zig").freeEvent(e);
        self.wh_events.deinit(alloc);
        self.wh_port_buf.deinit();
        self.wh_secret_buf.deinit();
        self.wh_url_buf.deinit();
        if (self.wh_secret.len > 0) alloc.free(self.wh_secret);
        if (self.wh_token.len > 0) alloc.free(self.wh_token);
        if (self.wh_note.len > 0) alloc.free(self.wh_note);
        self.add_path.deinit();
        if (self.add_note.len > 0) alloc.free(self.add_note);
        self.watch_repo.deinit();
        if (self.watch_note.len > 0) alloc.free(self.watch_note);
        for (self.decisions.items) |d| {
            if (!d.owned) continue;
            alloc.free(d.id);
            alloc.free(d.title);
            alloc.free(d.body);
            alloc.free(d.outcome);
            for (d.options) |o| alloc.free(o.detail);
            alloc.free(d.options);
            if (d.watch) |w| {
                alloc.free(w.repo);
                alloc.free(w.numbers);
                alloc.free(w.context);
            }
        }
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

    // --- Repo watches -----------------------------------------------------

    /// Validates the add-watch form and binds a new watcher; the baseline
    /// check fires on the next scheduler tick (~1s later).
    pub fn addWatcher(s: *State) void {
        const typed = std.mem.trimEnd(u8, s.watch_repo.text(), " \n\t");
        const slash = std.mem.indexOfScalar(u8, typed, '/') orelse {
            s.watchNote("仓库格式应为 owner/repo", true);
            return;
        };
        if (slash == 0 or slash == typed.len - 1 or std.mem.indexOfScalar(u8, typed[slash + 1 ..], '/') != null) {
            s.watchNote("仓库格式应为 owner/repo", true);
            return;
        }
        for (typed) |ch| {
            const ok = std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.' or ch == '/';
            if (!ok) {
                s.watchNote("仓库名只能包含字母数字、- _ . 和 /", true);
                return;
            }
        }
        if (!s.watch_prs and !s.watch_issues) {
            s.watchNote("至少选择 PR 或 issue 之一", true);
            return;
        }
        for (s.watchers.items) |entry| {
            if (std.mem.eql(u8, entry.info.repo, typed)) {
                s.watchNote("该仓库已在监听中", true);
                return;
            }
        }
        const repo = alloc.dupe(u8, typed) catch return;
        if (s.bindWatcher(repo, s.watch_prs, s.watch_issues, s.watch_interval_min, true, 0, 0) == null) {
            s.watchNote("监听添加失败", true);
            return;
        }
        s.watch_repo.clear();
        s.watchNote("监听已添加，马上进行首次检查", false);
        s.page = .{ .watch = s.watchers.items.len - 1 };
        s.saveWatchers();
    }

    /// Creates the runtime and entry for a watcher (shared by the form and
    /// the persisted list loaded at launch). Takes ownership of `repo`.
    fn bindWatcher(s: *State, repo: []u8, prs: bool, issues: bool, interval_min: u32, enabled: bool, checks: u32, findings: u32) ?*WatchEntry {
        const engine = @import("fx");
        const runtime = agent.Runtime.create(s.cwd) catch {
            alloc.free(repo);
            return null;
        };
        const entry = alloc.create(WatchEntry) catch {
            runtime.deinit();
            alloc.free(repo);
            return null;
        };
        entry.* = .{
            .info = .{
                .repo = repo,
                .watch_prs = prs,
                .watch_issues = issues,
                .interval_min = interval_min,
                .added_ms = engine.shared_io.milliTimestamp(),
            },
            .runtime = runtime,
            .app = s,
            .enabled = enabled,
            .checks = checks,
            .findings = findings,
            // 0 means "due now": the next tick runs the check right away.
            .next_fire_ms = 0,
        };
        runtime.setCallback(entry, onWatchEvent);
        s.watchers.append(alloc, entry) catch {
            entry.deinit();
            return null;
        };
        return entry;
    }

    pub fn removeWatcher(s: *State, index: usize) void {
        if (index >= s.watchers.items.len) return;
        const entry = s.watchers.orderedRemove(index);
        entry.deinit();
        switch (s.page) {
            .watch => |wi| if (wi == index) {
                s.page = .watchers;
            },
            else => {},
        }
        s.saveWatchers();
    }

    pub fn toggleWatcher(s: *State, index: usize) void {
        if (index >= s.watchers.items.len) return;
        const entry = s.watchers.items[index];
        entry.enabled = !entry.enabled;
        // Re-check right away when resumed.
        if (entry.enabled) entry.next_fire_ms = 0;
        s.saveWatchers();
    }

    /// Lets the scheduler fire this watcher on the next tick.
    pub fn checkWatcherNow(s: *State, index: usize) void {
        if (index >= s.watchers.items.len) return;
        s.watchers.items[index].next_fire_ms = 0;
    }

    /// Builds the check instruction (the first run establishes a baseline)
    /// and starts the watcher's fx turn; the reply is parsed when it ends.
    fn fireWatch(s: *State, entry: *WatchEntry) void {
        const engine = @import("fx");
        const prev_check_ms = entry.last_check_ms;
        entry.checks += 1;
        entry.last_check_ms = engine.shared_io.milliTimestamp();
        entry.next_fire_ms = entry.last_check_ms + @as(i64, entry.info.interval_min) * 60_000;

        const scope: []const u8 = if (entry.info.watch_prs and entry.info.watch_issues)
            "新 PR 和 issue"
        else if (entry.info.watch_prs)
            "新 PR"
        else
            "新 issue";

        var ig: std.ArrayList(u8) = .empty;
        defer ig.deinit(alloc);
        if (entry.ignored.items.len > 0) {
            ig.appendSlice(alloc, "\n已忽略、不要报告的条目：") catch {};
            const ig_label = formatNumbers(entry.ignored.items);
            defer alloc.free(ig_label);
            ig.appendSlice(alloc, ig_label) catch {};
            ig.appendSlice(alloc, "。") catch {};
        }
        const ignored_clause: []const u8 = ig.items;

        var rp: std.ArrayList(u8) = .empty;
        defer rp.deinit(alloc);
        if (entry.reported.items.len > 0) {
            rp.appendSlice(alloc, "\n上次已汇报（不要重复报告）：") catch {};
            const recent = if (entry.reported.items.len > 24) entry.reported.items[entry.reported.items.len - 24 ..] else entry.reported.items;
            const rp_label = formatNumbers(recent);
            defer alloc.free(rp_label);
            rp.appendSlice(alloc, rp_label) catch {};
            rp.appendSlice(alloc, "。") catch {};
        }
        const reported_clause: []const u8 = rp.items;

        var tbuf: [8]u8 = undefined;
        const instruction = if (entry.checks == 1)
            alloc.print(
                \\[监听] 检查 GitHub 仓库 {s} 的{s}。
                \\用 gh 查询：gh pr list -R {s} --json number,title,author,createdAt,url --limit 30（issue 用 gh issue list，参数相同）；gh 不可用时用 curl 调 https://api.github.com/repos/{s}/pulls 或 /issues。
                \\这是首次检查：把当前 open 的最新 3 条作为基线列出来（跳过已忽略条目），回复以「基线已建立」结尾。{s}
            , .{ entry.info.repo, scope, entry.info.repo, entry.info.repo, reported_clause }) catch return
        else if (entry.reported.items.len == 0)
            // No history to diff against (e.g. the baseline found nothing
            // and items appeared since): list the current top, which also
            // bootstraps the reported set.
            alloc.print(
                \\[监听] 检查 GitHub 仓库 {s} 的{s}。
                \\用 gh 查询：gh pr list -R {s} --json number,title,author,createdAt,url --limit 30（issue 用 gh issue list，参数相同）；gh 不可用时用 curl 调 https://api.github.com/repos/{s}/pulls 或 /issues。
                \\没有历史记录可对比：把当前 open 的最新 3 条列出来（跳过已忽略条目），逐条「#编号 标题 — 链接」加一句中文说明，结尾写「共 N 条新动态」；一个 open 条目都没有就只回复：无新动态{s}
            , .{ entry.info.repo, scope, entry.info.repo, entry.info.repo, ignored_clause }) catch return
        else
            alloc.print(
                \\[监听] 检查 GitHub 仓库 {s} 的{s}（上次检查 {s}，结论：{s}）。
                \\用 gh 查询：gh pr list -R {s} --json number,title,author,createdAt,url --limit 30（issue 用 gh issue list，参数相同）；gh 不可用时用 curl 调 https://api.github.com/repos/{s}/pulls 或 /issues。
                \\对比上次已汇报的编号与本会话历史，只报告全新条目：逐条「#编号 标题 — 链接」加一句中文说明，结尾写「共 N 条新动态」。{s}
                \\没有新条目就只回复：无新动态{s}
            , .{
                entry.info.repo,
                scope,
                hhmm(&tbuf, if (prev_check_ms > 0) prev_check_ms else entry.last_check_ms),
                entry.last_result,
                entry.info.repo,
                entry.info.repo,
                reported_clause,
                ignored_clause,
            }) catch return;
        defer alloc.free(instruction);

        entry.thread.append(alloc, .{ .agent = null, .time = now(), .kind = .owner, .text = alloc.dupe(u8, instruction) catch return }) catch return;
        entry.runtime.start(instruction) catch {
            entry.thread.append(alloc, .{ .agent = seed.watcher, .time = now(), .kind = .note, .text = "fx agent 启动失败" }) catch {};
            return;
        };
        s.watch_seq += 1;
        const id = alloc.print("W-{d:0>4}", .{s.watch_seq}) catch "W-0000";
        const title = alloc.print("watch: {s}", .{entry.info.repo}) catch return;
        s.tasks.append(alloc, .{
            .id = id,
            .title = title,
            .role = "watcher",
            .host = "本机",
            .model = "fx",
            .status = .running,
            .started_min_ago = 0,
            .started_at_ms = entry.last_check_ms,
            .routine = true,
            .request = alloc.dupe(u8, instruction) catch "",
        }) catch {};
        entry.turn_task = @intCast(s.tasks.items.len - 1);
        entry.streaming = @intCast(entry.thread.items.len);
        entry.thread.append(alloc, .{ .agent = seed.watcher, .time = now(), .kind = .note, .text = "" }) catch {};
        s.saveWatchers();
        if (s.window) |window| window.redraw();
    }

    /// fx events from a watcher's runtime land here (the callback's context
    /// is the WatchEntry), appending to its check transcript.
    fn onWatchEvent(context: ?*anyopaque, event: agent.Event) void {
        const entry: *WatchEntry = @ptrCast(@alignCast(context.?));
        switch (event) {
            .text => |bytes| {
                entry.diag = -1;
                if (entry.streaming >= 0 and entry.streaming < entry.thread.items.len) {
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
                    entry.thread.append(alloc, .{ .agent = seed.watcher, .time = now(), .kind = .diag, .text = alloc.dupe(u8, bytes) catch return }) catch return;
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
                entry.thread.append(alloc, .{ .agent = seed.watcher, .time = now(), .kind = .tool, .text = line }) catch {};
            },
            .done => {
                entry.diag = -1;
                const reply: []const u8 = if (entry.streaming >= 0 and entry.streaming < entry.thread.items.len)
                    entry.thread.items[@intCast(entry.streaming)].text
                else
                    "";
                entry.streaming = -1;
                entry.app.finishWatch(entry, reply, null);
            },
            .failed => |bytes| {
                entry.diag = -1;
                entry.streaming = -1;
                entry.app.finishWatch(entry, "", bytes);
            },
        }
        if (entry.app.window) |window| window.redraw();
    }

    /// Wraps up a check: records the short result line, closes the task and
    /// routes the reply — "基线已建立" and "无新动态" stay quiet in the
    /// channel (the routine's convention), findings are reported.
    fn finishWatch(s: *State, entry: *WatchEntry, reply: []const u8, failure: ?[]const u8) void {
        var line: []const u8 = "（无回复）";
        if (failure != null) {
            line = alloc.print("检查失败：{s}", .{shorten(failure.?)}) catch "检查失败";
        } else if (reply.len > 0) {
            line = firstLine(reply);
        }
        s.setLastResult(entry, line);

        const cancelled = entry.turn_task < 0;
        if (!cancelled and entry.turn_task < s.tasks.items.len) {
            const task = &s.tasks.items[@intCast(entry.turn_task)];
            if (failure != null) {
                task.status = .failed;
                task.result = alloc.dupe(u8, shorten(failure.?)) catch "";
            } else {
                task.status = .done;
                task.result = alloc.dupe(u8, if (reply.len > 400) reply[0..400] else reply) catch "";
            }
        }
        entry.turn_task = -1;
        // Cancelled mid-turn: the transcript keeps whatever streamed, but
        // nothing is reported.
        if (cancelled) {
            s.saveWatchers();
            return;
        }

        if (failure != null) {
            const msg = alloc.print("【{s}】{s}", .{ entry.info.repo, line }) catch return;
            s.pushMessage(.{ .agent = seed.watcher, .time = now(), .kind = .note, .text = msg });
        } else if (std.mem.indexOf(u8, reply, "基线已建立") != null) {
            const numbers = parseNumbers(reply);
            defer alloc.free(numbers);
            mergeReported(entry, numbers);
            const msg = alloc.print("【{s}】基线已建立：{s}", .{ entry.info.repo, line }) catch return;
            s.pushMessage(.{ .agent = seed.watcher, .time = now(), .kind = .note, .text = msg });
        } else if (std.mem.indexOf(u8, reply, "无新动态") != null) {
            // Quiet per the routine's instruction: nothing worth surfacing.
        } else if (reply.len > 0) {
            entry.findings += 1;
            // New PRs/issues: ask the owner what to do about them. The
            // numbers also join the reported set so restarts never
            // re-report them.
            const numbers = parseNumbers(reply);
            mergeReported(entry, numbers);
            s.pushWatchDecision(entry, reply, numbers);
        }
        s.saveWatchers();
    }

    /// Numbers join the watcher's reported set (deduped, capped), so later
    /// checks — even after a restart — never treat them as new.
    fn mergeReported(entry: *WatchEntry, numbers: []const u32) void {
        for (numbers) |n| {
            var exists = false;
            for (entry.reported.items) |m| {
                if (m == n) {
                    exists = true;
                    break;
                }
            }
            if (!exists) entry.reported.append(alloc, n) catch {};
        }
        while (entry.reported.items.len > 100) _ = entry.reported.orderedRemove(0);
    }

    fn setLastResult(s: *State, entry: *WatchEntry, line: []const u8) void {
        _ = s;
        if (entry.last_result.len > 0) alloc.free(entry.last_result);
        entry.last_result = alloc.dupe(u8, line) catch &.{};
    }

    /// A watcher's finding becomes a decision card in the channel: A 快速
    ///审阅, B 派完整审查任务, C 忽略 (the numbers go on the watcher's
    /// persisted ignore list and are never reported again).
    fn pushWatchDecision(s: *State, entry: *WatchEntry, reply: []const u8, numbers: []const u32) void {
        var watcher_index: ?usize = null;
        for (s.watchers.items, 0..) |w, i| {
            if (w == entry) {
                watcher_index = i;
                break;
            }
        }
        const wi = watcher_index orelse {
            alloc.free(numbers);
            return;
        };
        s.decision_seq += 1;
        const id = alloc.print("D-{d:0>4}", .{s.decision_seq}) catch return;
        const title = alloc.print("处理 {s} 的新发现？", .{entry.info.repo}) catch return;
        const body_reply = if (reply.len > 280) reply[0..280] else reply;
        const body = alloc.print("watcher 在 {s} 发现：\n\n{s}", .{ entry.info.repo, body_reply }) catch return;
        const nums_label = formatNumbers(numbers);
        defer alloc.free(nums_label);
        const outcome = alloc.print("按所选方案处理 {s} 的新条目（{s}）", .{ entry.info.repo, nums_label }) catch return;
        const context = alloc.dupe(u8, if (reply.len > 200) reply[0..200] else reply) catch return;

        const options = alloc.alloc(model.Option, 3) catch return;
        // Keep each detail short: a single rendered line, so the options
        // stay readable — and exactly matchable by the headless tester.
        options[0] = .{
            .label = "A",
            .detail = alloc.print("快速审阅 — 拉 diff 给审阅意见", .{}) catch return,
        };
        options[1] = .{
            .label = "B",
            .detail = alloc.print("派任务 — 完整审查，输出结构化报告", .{}) catch return,
        };
        options[2] = .{
            .label = "C",
            .detail = alloc.print("忽略 — 不再汇报这些条目", .{}) catch return,
        };

        s.decisions.append(alloc, .{
            .id = id,
            .title = title,
            .body = body,
            .options = options,
            .outcome = outcome,
            .owned = true,
            .watch = .{
                .watcher = wi,
                .repo = alloc.dupe(u8, entry.info.repo) catch return,
                .numbers = numbers,
                .context = context,
            },
        }) catch return;
        s.pushMessage(.{
            .agent = seed.watcher,
            .time = now(),
            .kind = .decision,
            .text = "",
            .decision = @intCast(s.decisions.items.len - 1),
        });
    }

    /// Runs the review the owner picked on a watcher decision: option A is a
    /// quick pass, B a full review; both stream through the hub runtime as a
    /// tracked task. Issue-only watches review issues; PR watches diff PRs.
    fn dispatchWatchReview(s: *State, w: model.WatchRef, deep: bool) void {
        if (w.watcher >= s.watchers.items.len) return;
        const watch_info = s.watchers.items[w.watcher].info;
        if (!std.mem.eql(u8, watch_info.repo, w.repo)) return;
        const issue_mode = watch_info.watch_issues and !watch_info.watch_prs;
        const nums_label = formatNumbers(w.numbers);
        defer alloc.free(nums_label);

        const instruction = if (w.numbers.len == 0)
            alloc.print("审查 GitHub 仓库 {s} 的这些新条目：\n{s}\n\n用 gh（或 curl GitHub API）找到相关的 PR 或 issue，逐个拉取内容审阅：问题列表（标严重度）、测试缺口、处理建议。中文回复。", .{
                w.repo,
                w.context,
            }) catch return
        else if (issue_mode)
            alloc.print("查看 GitHub 仓库 {s} 的这些 issue：{s}。对每个编号运行 gh issue view <编号> -R {s} --json title,body,author,comments（gh 不可用就 curl https://api.github.com/repos/{s}/issues/<编号>），总结内容并评估是否需要处理，每个 issue 给出处理建议。中文回复。", .{ w.repo, nums_label, w.repo, w.repo }) catch return
        else if (deep)
            alloc.print("完整审查 GitHub 仓库 {s} 的这些 PR：{s}。对每个编号运行 gh pr diff {s} <编号>（gh 不可用就 curl -L https://github.com/{s}/pull/<编号>.diff）拉取 diff，逐文件检查正确性、安全、性能与测试覆盖。输出结构化审查报告，每个 PR 一节：问题清单（严重度 + 文件:行）、测试缺口、是否可合并。中文回复。", .{ w.repo, nums_label, w.repo, w.repo }) catch return
        else
            alloc.print("快速审阅 GitHub 仓库 {s} 的这些 PR：{s}。对每个编号运行 gh pr diff {s} <编号>（gh 不可用就 curl -L https://github.com/{s}/pull/<编号>.diff）拉取 diff，检查正确性与破坏性变更，每个 PR 给出问题列表（标严重度）和合并建议。中文回复。", .{ w.repo, nums_label, w.repo, w.repo }) catch return;
        defer alloc.free(instruction);

        const runtime = s.runtime.?;
        if (runtime.busy()) {
            s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = "团队在忙上一个任务，这条审查先记下，空闲后重新发起" });
            return;
        }
        runtime.start(instruction) catch {
            s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = "fx agent 启动失败" });
            return;
        };
        s.task_seq += 1;
        const id = alloc.print("T-{d:0>4}", .{s.task_seq}) catch return;
        const title = alloc.print("review: {s} {s}", .{ w.repo, nums_label }) catch return;
        s.tasks.append(alloc, .{
            .id = id,
            .title = shorten(title),
            .role = "hub",
            .host = "本机",
            .model = "fx",
            .status = .running,
            .started_min_ago = 0,
            .started_at_ms = @import("fx").shared_io.milliTimestamp(),
            .request = alloc.dupe(u8, instruction) catch "",
        }) catch {};
        s.turn_task = @intCast(s.tasks.items.len - 1);
        s.turn_runtime = runtime;
        s.turn_project = null;
        s.streaming = @intCast(s.messages.items.len);
        s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = "" });
    }

    /// Option C on a watcher decision: the numbers join the watcher's
    /// ignore list (persisted), so later checks never report them again.
    fn ignoreWatchFinding(s: *State, w: model.WatchRef) void {
        if (w.watcher >= s.watchers.items.len) return;
        const entry = s.watchers.items[w.watcher];
        if (!std.mem.eql(u8, entry.info.repo, w.repo)) return;
        for (w.numbers) |n| {
            var exists = false;
            for (entry.ignored.items) |m| {
                if (m == n) {
                    exists = true;
                    break;
                }
            }
            if (!exists) entry.ignored.append(alloc, n) catch {};
        }
        s.saveWatchers();
    }

    // --- GitHub webhook receiver ------------------------------------------

    /// Loads ~/.nanodot/settings.json, generates the hook token on first
    /// run, and starts the receiver when enabled.
    fn loadWebhook(s: *State) void {
        const engine = @import("fx");
        const home = engine.shared_io.homeDir() orelse return;
        const path = alloc.print("{s}/.nanodot/settings.json", .{home}) catch return;
        defer alloc.free(path);
        if (readFile(path)) |data| {
            defer alloc.free(data);
            var parsed = std.json.parseFromSlice(std.json.Value, alloc, data, .{}) catch null;
            if (parsed) |*p| {
                defer p.deinit();
                if (p.value == .object) {
                    if (p.value.object.get("webhook")) |wh| {
                        if (wh == .object) {
                            const o = wh.object;
                            if (o.get("enabled")) |v| {
                                if (v == .bool) s.wh_enabled = v.bool;
                            }
                            if (o.get("port")) |v| {
                                if (v == .integer) s.wh_port = @intCast(@max(1, @min(65535, v.integer)));
                            }
                            if (o.get("secret")) |v| {
                                if (v == .string and v.string.len > 0) {
                                    s.wh_secret = alloc.dupe(u8, v.string) catch &.{};
                                }
                            }
                            if (o.get("token")) |v| {
                                if (v == .string and v.string.len > 0) {
                                    s.wh_token = alloc.dupe(u8, v.string) catch &.{};
                                }
                            }
                        }
                    }
                }
            }
        }
        var need_save = false;
        if (s.wh_token.len == 0) {
            var bytes: [16]u8 = undefined;
            engine.shared_io.getIo().random(&bytes);
            const hex = std.fmt.bytesToHex(bytes, .lower);
            s.wh_token = alloc.dupe(u8, &hex) catch return;
            need_save = true;
        }
        var pb: [8]u8 = undefined;
        const port_text = std.fmt.bufPrint(&pb, "{d}", .{s.wh_port}) catch "9781";
        s.wh_port_buf.set(port_text);
        if (s.wh_secret.len > 0) s.wh_secret_buf.set(s.wh_secret);
        s.refreshWebhookUrl();
        if (s.wh_enabled) s.applyWebhook(true);
        if (need_save) s.saveWebhookConfig();
    }

    fn saveWebhookConfig(s: *State) void {
        const engine = @import("fx");
        const home = engine.shared_io.homeDir() orelse return;
        const dir_path = alloc.print("{s}/.nanodot", .{home}) catch return;
        defer alloc.free(dir_path);
        std.Io.Dir.cwd().createDirPath(engine.shared_io.getIo(), dir_path) catch return;
        const path = alloc.print("{s}/settings.json", .{dir_path}) catch return;
        defer alloc.free(path);
        const text = alloc.print("{{\"webhook\":{{\"enabled\":{s},\"port\":{d},\"token\":\"{s}\",\"secret\":\"{s}\"}}}}", .{
            if (s.wh_enabled) "true" else "false",
            s.wh_port,
            s.wh_token,
            s.wh_secret,
        }) catch return;
        defer alloc.free(text);
        engine.shared_io.writeFileAtomic(alloc, path, text) catch {};
    }

    /// (Re)starts or stops the receiver to match the current config.
    fn applyWebhook(s: *State, quiet: bool) void {
        if (s.webhook) |server| {
            server.stop();
            s.webhook = null;
        }
        if (!s.wh_enabled) {
            if (!quiet) s.whNote("webhook 已停止", false);
            return;
        }
        const server = @import("webhook.zig").Server.create(s.wh_port, s.wh_token, s.wh_secret) catch {
            if (!quiet) s.whNote("webhook 服务创建失败", true);
            return;
        };
        server.start() catch |err| {
            server.stop();
            if (!quiet) s.whNote(alloc.print("端口 {d} 启动失败：{s}", .{ s.wh_port, @errorName(err) }) catch "启动失败", true);
            return;
        };
        s.webhook = server;
        if (!quiet) s.whNote(alloc.print("webhook 运行中：http://127.0.0.1:{d}/hook/{s}", .{ s.wh_port, s.wh_token }) catch "运行中", false);
    }

    /// Settings-page save: validate the port field, take the secret, persist
    /// and restart the receiver.
    pub fn saveWebhookFromForm(s: *State) void {
        const port_text = std.mem.trimEnd(u8, s.wh_port_buf.text(), " \n\t");
        const port = std.fmt.parseInt(u16, port_text, 10) catch {
            s.whNote("端口应为 1024-65535 的数字", true);
            return;
        };
        if (port < 1024) {
            s.whNote("端口应在 1024-65535 之间", true);
            return;
        }
        const secret = std.mem.trimEnd(u8, s.wh_secret_buf.text(), " \n\t");
        const owned = alloc.dupe(u8, secret) catch return;
        if (s.wh_secret.len > 0) alloc.free(s.wh_secret);
        s.wh_secret = owned;
        s.wh_port = port;
        s.saveWebhookConfig();
        s.refreshWebhookUrl();
        s.applyWebhook(true);
        s.whNote(if (s.wh_enabled) "已保存并应用，webhook 运行中" else "已保存；启用后生效", false);
    }

    pub fn toggleWebhook(s: *State) void {
        s.wh_enabled = !s.wh_enabled;
        s.saveWebhookConfig();
        s.applyWebhook(true);
        s.whNote(if (s.wh_enabled) "webhook 已启用并运行" else "webhook 已停用", false);
    }

    fn refreshWebhookUrl(s: *State) void {
        var buf: [128]u8 = undefined;
        const url = std.fmt.bufPrint(&buf, "http://127.0.0.1:{d}/hook/{s}", .{ s.wh_port, s.wh_token }) catch return;
        s.wh_url_buf.set(url);
    }

    /// A delivery from the receiver thread: log it, and wake the watcher
    /// for the event's repo so the check runs within ~1s.
    pub fn onWebhookEvent(s: *State, e: @import("webhook.zig").Event) void {
        if (s.wh_events.items.len >= 20) {
            const old = s.wh_events.orderedRemove(0);
            @import("webhook.zig").freeEvent(old);
        }
        s.wh_events.append(alloc, e) catch {
            @import("webhook.zig").freeEvent(e);
            return;
        };
        if (e.repo.len > 0) {
            for (s.watchers.items, 0..) |w, i| {
                if (std.mem.eql(u8, w.info.repo, e.repo)) {
                    s.checkWatcherNow(i);
                    break;
                }
            }
        }
        if (s.window) |window| window.redraw();
    }

    fn whNote(s: *State, text: []const u8, fail: bool) void {
        if (s.wh_note.len > 0) alloc.free(s.wh_note);
        s.wh_note = alloc.dupe(u8, text) catch &.{};
        s.wh_note_err = fail;
        if (s.window) |window| window.redraw();
    }

    /// The watch scheduler: re-arms itself every second and starts a check
    /// for each watcher whose interval came due (a Grok Bot-style routine:
    /// the app wakes the agent on a schedule, the agent polls GitHub). Also
    /// drains webhook deliveries queued by the receiver thread.
    fn tickMain(context: ?*anyopaque) callconv(.c) void {
        const s: *State = @ptrCast(@alignCast(context.?));
        const now_ms = @import("fx").shared_io.milliTimestamp();
        for (s.watchers.items) |entry| {
            if (!entry.enabled or entry.runtime.busy()) continue;
            if (now_ms < entry.next_fire_ms) continue;
            s.fireWatch(entry);
        }
        if (s.webhook) |server| {
            while (server.pop()) |event| s.onWebhookEvent(event);
        }
        nanoui.App.after(1000, s, tickMain);
    }

    /// ~/.nanodot/watchers.json — the watch list survives restarts; the
    /// transcript and fx session do not.
    fn saveWatchers(s: *State) void {
        const engine = @import("fx");
        const home = engine.shared_io.homeDir() orelse return;
        const dir_path = alloc.print("{s}/.nanodot", .{home}) catch return;
        defer alloc.free(dir_path);
        std.Io.Dir.cwd().createDirPath(engine.shared_io.getIo(), dir_path) catch return;
        const path = alloc.print("{s}/watchers.json", .{dir_path}) catch return;
        defer alloc.free(path);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);
        buf.appendSlice(alloc, "{\"watchers\":[") catch return;
        for (s.watchers.items, 0..) |entry, i| {
            if (i > 0) buf.appendSlice(alloc, ",") catch return;
            var ig: std.ArrayList(u8) = .empty;
            defer ig.deinit(alloc);
            ig.appendSlice(alloc, "[") catch return;
            for (entry.ignored.items, 0..) |n, k| {
                if (k > 0) ig.appendSlice(alloc, ",") catch return;
                const piece = alloc.print("{d}", .{n}) catch return;
                defer alloc.free(piece);
                ig.appendSlice(alloc, piece) catch return;
            }
            ig.appendSlice(alloc, "]") catch return;
            var rp: std.ArrayList(u8) = .empty;
            defer rp.deinit(alloc);
            rp.appendSlice(alloc, "[") catch return;
            for (entry.reported.items, 0..) |n, k| {
                if (k > 0) rp.appendSlice(alloc, ",") catch return;
                const piece = alloc.print("{d}", .{n}) catch return;
                defer alloc.free(piece);
                rp.appendSlice(alloc, piece) catch return;
            }
            rp.appendSlice(alloc, "]") catch return;
            const item = alloc.print("{{\"repo\":\"{s}\",\"prs\":{s},\"issues\":{s},\"interval_min\":{d},\"enabled\":{s},\"checks\":{d},\"findings\":{d},\"ignored\":{s},\"reported\":{s}}}", .{
                entry.info.repo,
                if (entry.info.watch_prs) "true" else "false",
                if (entry.info.watch_issues) "true" else "false",
                entry.info.interval_min,
                if (entry.enabled) "true" else "false",
                entry.checks,
                entry.findings,
                ig.items,
                rp.items,
            }) catch return;
            defer alloc.free(item);
            buf.appendSlice(alloc, item) catch return;
        }
        buf.appendSlice(alloc, "]}") catch return;
        engine.shared_io.writeFileAtomic(alloc, path, buf.items) catch {};
    }

    fn loadWatchers(s: *State) void {
        const engine = @import("fx");
        const home = engine.shared_io.homeDir() orelse return;
        const path = alloc.print("{s}/.nanodot/watchers.json", .{home}) catch return;
        defer alloc.free(path);
        const data = readFile(path) orelse return;
        defer alloc.free(data);
        var parsed = std.json.parseFromSlice(std.json.Value, alloc, data, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const list = parsed.value.object.get("watchers") orelse return;
        if (list != .array) return;
        for (list.array.items) |item| {
            if (item != .object) continue;
            const obj = item.object;
            const repo_v = obj.get("repo") orelse continue;
            if (repo_v != .string) continue;
            var prs = true;
            if (obj.get("prs")) |v| {
                if (v == .bool) prs = v.bool;
            }
            var issues = false;
            if (obj.get("issues")) |v| {
                if (v == .bool) issues = v.bool;
            }
            var interval: u32 = 15;
            if (obj.get("interval_min")) |v| {
                if (v == .integer) interval = @intCast(@max(1, @min(24 * 60, v.integer)));
            }
            var enabled = true;
            if (obj.get("enabled")) |v| {
                if (v == .bool) enabled = v.bool;
            }
            var checks: u32 = 0;
            if (obj.get("checks")) |v| {
                if (v == .integer) checks = @intCast(@max(0, @min(1_000_000, v.integer)));
            }
            var findings: u32 = 0;
            if (obj.get("findings")) |v| {
                if (v == .integer) findings = @intCast(@max(0, @min(1_000_000, v.integer)));
            }
            const repo = alloc.dupe(u8, repo_v.string) catch continue;
            const entry = s.bindWatcher(repo, prs, issues, interval, enabled, checks, findings) orelse continue;
            if (obj.get("ignored")) |v| {
                if (v == .array) {
                    for (v.array.items) |n| {
                        if (n == .integer) {
                            const num: u32 = @intCast(@max(0, @min(1_000_000_000, n.integer)));
                            entry.ignored.append(alloc, num) catch {};
                        }
                    }
                }
            }
            if (obj.get("reported")) |v| {
                if (v == .array) {
                    for (v.array.items) |n| {
                        if (n == .integer) {
                            const num: u32 = @intCast(@max(0, @min(1_000_000_000, n.integer)));
                            entry.reported.append(alloc, num) catch {};
                        }
                    }
                }
            }
        }
    }

    fn watchNote(s: *State, text: []const u8, fail: bool) void {
        if (s.watch_note.len > 0) alloc.free(s.watch_note);
        s.watch_note = alloc.dupe(u8, text) catch &.{};
        s.watch_note_err = fail;
        if (s.window) |window| window.redraw();
    }

    fn addNote(s: *State, text: []const u8, fail: bool) void {
        if (s.add_note.len > 0) alloc.free(s.add_note);
        s.add_note = alloc.dupe(u8, text) catch &.{};
        s.add_note_err = fail;
        if (s.window) |window| window.redraw();
    }

    /// Cancel the agent turn `index` belongs to, if it is the live one.
    pub fn cancelTask(s: *State, index: usize) void {
        if (s.turn_task == index) {
            if (s.turn_runtime) |runtime| runtime.cancel() else if (s.runtime) |runtime| runtime.cancel();
            if (index < s.tasks.items.len) {
                s.tasks.items[index].status = .cancelled;
            }
            s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .note, .text = "收到：取消该任务 — fx 回合已中止" });
            s.streaming = -1;
            s.diag = -1;
            s.turn_task = -1;
            s.turn_runtime = null;
            return;
        }
        // A watcher check owns its turn through the WatchEntry.
        for (s.watchers.items) |entry| {
            if (entry.turn_task != index) continue;
            entry.runtime.cancel();
            entry.streaming = -1;
            entry.turn_task = -1;
            if (index < s.tasks.items.len) {
                s.tasks.items[index].status = .cancelled;
            }
            s.pushMessage(.{ .agent = seed.watcher, .time = now(), .kind = .note, .text = "收到：取消该检查 — fx 回合已中止" });
            return;
        }
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
        if (!s.tick_armed) {
            // Arm the watch scheduler from the first real frame; tests that
            // only build state never get here, so no timers without an app.
            s.tick_armed = true;
            nanoui.App.after(1000, s, tickMain);
        }
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
        if (d.watch) |w| {
            // Option C (忽略) dismisses the numbers; A/B start a review.
            if (option == 2) {
                s.ignoreWatchFinding(w);
            } else {
                s.dispatchWatchReview(w, option == 1);
            }
        }
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
                    // Own the bytes: the event's buffer is freed once this
                    // callback returns, and later growth of this card would
                    // otherwise copy out of freed (possibly reallocated)
                    // memory — which @memcpy rejects as aliasing.
                    s.pushMessage(.{ .agent = seed.hub, .time = now(), .kind = .diag, .text = alloc.dupe(u8, bytes) catch return });
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

/// The first line of a check reply, trimmed for the status line and for
/// feeding into the next check's instruction.
fn firstLine(text: []const u8) []const u8 {
    var line = text;
    if (std.mem.indexOfScalar(u8, line, '\n')) |nl| line = line[0..nl];
    line = std.mem.trimEnd(u8, line, " \t\r");
    if (line.len > 80) line = line[0..80];
    return line;
}

/// PR/issue numbers ("#1602") in a finding reply, unique, at most 8.
fn parseNumbers(text: []const u8) []u32 {
    var list: std.ArrayList(u32) = .empty;
    errdefer list.deinit(alloc);
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] != '#' or i + 1 >= text.len or !std.ascii.isDigit(text[i + 1])) continue;
        var value: u32 = 0;
        var j = i + 1;
        while (j < text.len and std.ascii.isDigit(text[j]) and j < i + 7) : (j += 1) {
            value = value *% 10 +% (text[j] - '0');
        }
        var exists = false;
        for (list.items) |n| {
            if (n == value) {
                exists = true;
                break;
            }
        }
        if (!exists) list.append(alloc, value) catch {};
        i = j;
    }
    return list.toOwnedSlice(alloc) catch &.{};
}

/// "#1602、#1603" for instructions and decision option text.
fn formatNumbers(numbers: []const u32) []u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);
    for (numbers, 0..) |n, i| {
        if (i > 0) buf.appendSlice(alloc, "、") catch {};
        const piece = alloc.print("#{d}", .{n}) catch continue;
        defer alloc.free(piece);
        buf.appendSlice(alloc, piece) catch {};
    }
    if (buf.items.len == 0) buf.appendSlice(alloc, "新条目") catch {};
    return buf.toOwnedSlice(alloc) catch alloc.dupe(u8, "新条目") catch @panic("oom");
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

pub fn hhmm(buf: []u8, ms: i64) []const u8 {
    const secs: u64 = @intCast(@max(0, @divFloor(ms, 1000)));
    const hh = (secs / 3600 + 8) % 24; // demo clock, fixed to UTC+8
    const mm = (secs / 60) % 60;
    return std.mem.print(buf, "{d:0>2}:{d:0>2}", .{ hh, mm }) catch "??:??";
}

fn now() []const u8 {
    return hhmm(&clock_buf, @import("fx").shared_io.milliTimestamp());
}

test "watcher finding becomes a decision; ignore dismisses its numbers" {
    const engine = @import("fx");
    const home = engine.shared_io.homeDir() orelse return;
    const dir_path = try alloc.print("{s}/.nanodot", .{home});
    defer alloc.free(dir_path);
    const path = try alloc.print("{s}/watchers.json", .{dir_path});
    defer alloc.free(path);
    const preexisting = blk: {
        const io = engine.shared_io.getIo();
        var f = std.Io.Dir.openFileAbsolute(io, path, .{}) catch break :blk false;
        f.close(io);
        break :blk true;
    };

    const s = try State.create();
    defer s.destroy();
    const repo = try alloc.dupe(u8, "o/r");
    const entry = s.bindWatcher(repo, true, false, 15, true, 0, 0).?;
    try std.testing.expectEqual(@as(usize, 3), s.pendingCount());

    const reply = "发现新 PR：\n#12 Alpha — https://x/12\n#34 Beta — https://x/34\n共 2 条新动态";
    const numbers = parseNumbers(reply);
    try std.testing.expectEqualSlices(u32, &.{ 12, 34 }, numbers);
    s.pushWatchDecision(entry, reply, numbers);
    try std.testing.expectEqual(@as(usize, 4), s.decisions.items.len);
    try std.testing.expectEqual(@as(usize, 4), s.pendingCount());
    const di = s.decisions.items.len - 1;
    const w = s.decisions.items[di].watch;
    try std.testing.expect(w != null);
    try std.testing.expectEqualSlices(u32, &.{ 12, 34 }, w.?.numbers);

    // Option C: ignore — numbers join the watcher's persisted ignore list.
    s.choose(di, 2);
    try std.testing.expect(s.decisions.items[di].choice != null);
    try std.testing.expectEqual(@as(usize, 2), entry.ignored.items.len);
    const data = readFile(path) orelse return error.TestUnexpectedResult;
    defer alloc.free(data);
    try std.testing.expect(std.mem.indexOf(u8, data, "\"ignored\":[12,34]") != null);

    if (!preexisting) {
        const io = engine.shared_io.getIo();
        std.Io.Dir.deleteFileAbsolute(io, path) catch {};
        std.Io.Dir.deleteDirAbsolute(io, dir_path) catch {};
    }
}

