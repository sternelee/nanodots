//! The console's data model: agents, decisions, tasks, machines and channel
//! messages. Seed data lives in seed.zig; the running app appends to the
//! ArrayLists here as agents report and decisions resolve.
const std = @import("std");

pub const Agent = struct {
    name: []const u8,
    /// The avatar's letter and color.
    letter: u8,
    color: u24,
};

pub const Option = struct {
    label: []const u8,
    detail: []const u8,
};

pub const Decision = struct {
    id: []const u8,
    title: []const u8,
    /// The agent's analysis, shown above the options.
    body: []const u8,
    options: []const Option,
    /// null while pending; the chosen index once resolved.
    choice: ?usize = null,
    /// The instruction sent back to the team on resolve, for the confirm line.
    outcome: []const u8,
};

pub const TaskStatus = enum {
    running,
    queued,
    waiting,
    failed,
    done,
    cancelled,

    pub fn label(s: TaskStatus) []const u8 {
        return switch (s) {
            .running => "进行中",
            .queued => "排队中",
            .waiting => "等外部结果",
            .failed => "失败",
            .done => "完成",
            .cancelled => "已取消",
        };
    }
};

pub const Task = struct {
    id: []const u8,
    title: []const u8,
    role: []const u8,
    host: []const u8,
    model: []const u8,
    status: TaskStatus,
    /// Minutes before launch the task started (a seed value, shown as-is
    /// for finished tasks).
    started_min_ago: i64,
    /// When a running task actually started, for the live "N 分钟" label.
    started_at_ms: i64 = 0,
    routine: bool = false,
    /// The project this task belongs to, when dispatched through one.
    project: ?usize = null,
    request: []const u8,
    result: []const u8 = "",
    result_status: []const u8 = "",
    progress: []const []const u8 = &.{},
};

pub const Machine = struct {
    name: []const u8,
    kind: []const u8,
    online: bool,
    load_pct: u8,
    cores: u8,
    mem_pct: u8,
    disk_free_gb: u32,
    tools: []const []const u8,
    heartbeat: []const u8,
};

/// A workspace directory the owner added; instructions from the composer
/// run in the selected project's directory with its own fx session.
pub const Project = struct {
    name: []const u8,
    path: []const u8,
    added_ms: i64,
};

/// A GitHub repo watched for new PRs/issues. The app wakes the embedded
/// agent on an interval to check it (a Grok Bot-style routine): the reply
/// "无新动态" keeps it quiet, anything else is reported to the channel.
pub const Watch = struct {
    /// "owner/repo" on GitHub.
    repo: []const u8,
    watch_prs: bool,
    watch_issues: bool,
    interval_min: u32,
    added_ms: i64,
};

pub const Message = struct {
    pub const Kind = enum {
        /// A plain agent report.
        note,
        /// An embedded decision card; `decision` indexes State.decisions.
        decision,
        /// The owner's reply, right-aligned like the film.
        owner,
        /// One fx tool call the agent made: `text` is "name · status".
        tool,
        /// Collected stderr/stdout lines fx streamed mid-turn, one card.
        diag,
    };

    agent: ?Agent,
    time: []const u8,
    kind: Kind,
    text: []const u8 = "",
    decision: ?usize = null,
};

pub const alloc = std.heap.c_allocator;
