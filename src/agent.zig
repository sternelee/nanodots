//! The embedded fx agent runtime, in the manner of nanoterm's
//! agent_native.zig: one worker thread runs fx's in-process engine; its
//! callbacks queue events under a mutex; `nanoui.App.after` pumps them onto
//! the UI thread, where the app applies them to its state.
const std = @import("std");
const nanoui = @import("nanoui");
const engine = @import("fx");

const alloc = std.heap.c_allocator;

var threaded_io: std.Io.Threaded = undefined;
var io_ready = false;

/// fx's core needs an explicit std.Io on its worker thread.
fn initIo() void {
    if (io_ready) return;
    threaded_io = .init(alloc, .{});
    engine.shared_io.setIo(threaded_io.io());
    io_ready = true;
}

pub const Event = union(enum) {
    text: []u8,
    diagnostic: []u8,
    tool: struct {
        name: []u8,
        status: []u8,
        output: []u8,
    },
    done: struct {
        session_id: []u8,
        model: []u8,
    },
    failed: []u8,
};

/// One conversation with the embedded agent. The worker owns nothing but the
/// queue; the app applies events on the UI thread through `callback`.
pub const Runtime = struct {
    mutex: std.Io.Mutex = .init,
    events: std.ArrayList(Event) = .empty,
    worker: ?std.Thread = null,
    prompt: ?[]u8 = null,
    cwd: []u8,
    session_id: ?[]u8 = null,
    cancelled: std.atomic.Value(bool) = .init(false),
    running: std.atomic.Value(bool) = .init(false),
    scheduled: std.atomic.Value(bool) = .init(false),
    refs: std.atomic.Value(usize) = .init(1),
    callback: ?*const fn (?*anyopaque, Event) void = null,
    callback_context: ?*anyopaque = null,

    pub fn create(cwd: []const u8) !*Runtime {
        initIo();
        const self = try alloc.create(Runtime);
        errdefer alloc.destroy(self);
        self.* = .{ .cwd = try alloc.dupe(u8, cwd) };
        return self;
    }

    pub fn deinit(self: *Runtime) void {
        self.cancel();
        if (self.worker) |worker| worker.join();
        self.worker = null;
        self.callback = null;
        self.callback_context = null;
        self.release();
    }

    pub fn setCallback(self: *Runtime, context: ?*anyopaque, callback: *const fn (?*anyopaque, Event) void) void {
        self.callback_context = context;
        self.callback = callback;
    }

    pub fn busy(self: *Runtime) bool {
        return self.running.load(.acquire);
    }

    pub fn start(self: *Runtime, prompt: []const u8) !void {
        if (self.busy()) return error.Busy;
        if (self.worker) |worker| worker.join();
        self.worker = null;
        const owned = try alloc.dupe(u8, prompt);
        if (self.prompt) |old| alloc.free(old);
        self.prompt = owned;
        self.cancelled.store(false, .release);
        self.running.store(true, .release);
        // Arm the main-thread pump here, not from the worker: platform
        // timers must be created on the UI thread.
        self.schedule();
        self.worker = std.Thread.spawn(.{}, threadMain, .{self}) catch |err| {
            self.running.store(false, .release);
            return err;
        };
    }

    pub fn cancel(self: *Runtime) void {
        self.cancelled.store(true, .release);
    }

    fn retain(self: *Runtime) void {
        _ = self.refs.fetchAdd(1, .acq_rel);
    }

    fn release(self: *Runtime) void {
        if (self.refs.fetchSub(1, .acq_rel) != 1) return;
        for (self.events.items) |event| freeEvent(event);
        self.events.deinit(alloc);
        if (self.prompt) |prompt| alloc.free(prompt);
        if (self.session_id) |id| alloc.free(id);
        alloc.free(self.cwd);
        alloc.destroy(self);
    }

    fn schedule(self: *Runtime) void {
        if (self.scheduled.swap(true, .acq_rel)) return;
        self.retain();
        nanoui.App.after(8, self, drainMain);
    }

    fn drainMain(context: ?*anyopaque) callconv(.c) void {
        const self: *Runtime = @ptrCast(@alignCast(context.?));
        self.scheduled.store(false, .release);
        while (true) {
            const event = blk: {
                self.mutex.lockUncancelable(threaded_io.io());
                defer self.mutex.unlock(threaded_io.io());
                if (self.events.items.len == 0) break :blk null;
                break :blk self.events.orderedRemove(0);
            } orelse break;
            if (self.callback) |callback| callback(self.callback_context, event);
            freeEvent(event);
        }
        if (self.busy() or self.hasEvents()) self.schedule();
        self.release();
    }

    fn hasEvents(self: *Runtime) bool {
        self.mutex.lockUncancelable(threaded_io.io());
        defer self.mutex.unlock(threaded_io.io());
        return self.events.items.len != 0;
    }

    fn emit(self: *Runtime, event: Event) !void {
        self.mutex.lockUncancelable(threaded_io.io());
        defer self.mutex.unlock(threaded_io.io());
        try self.events.append(alloc, event);
    }

    fn text(context: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *Runtime = @ptrCast(@alignCast(context.?));
        try self.emit(.{ .text = try alloc.dupe(u8, bytes) });
    }

    fn diagnostic(context: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *Runtime = @ptrCast(@alignCast(context.?));
        try self.emit(.{ .diagnostic = try alloc.dupe(u8, bytes) });
    }

    fn tool(context: ?*anyopaque, name: []const u8, status: []const u8, output: []const u8) anyerror!void {
        const self: *Runtime = @ptrCast(@alignCast(context.?));
        try self.emit(.{ .tool = .{
            .name = try alloc.dupe(u8, name),
            .status = try alloc.dupe(u8, status),
            .output = try alloc.dupe(u8, output),
        } });
    }

    fn threadMain(self: *Runtime) void {
        defer self.running.store(false, .release);
        const result = engine.run(alloc, self.prompt.?, self.cwd, self.session_id, null, &.{}, &self.cancelled, .{
            .context = self,
            .text = text,
            .diagnostic = diagnostic,
            .tool = tool,
        }, null) catch |err| {
            const message = alloc.dupe(u8, @errorName(err)) catch return;
            self.emit(.{ .failed = message }) catch alloc.free(message);
            return;
        };
        defer result.deinit(alloc);
        if (result.session_id.len > 0) {
            if (self.session_id) |old| alloc.free(old);
            self.session_id = alloc.dupe(u8, result.session_id) catch null;
        }
        self.emit(.{ .done = .{
            .session_id = alloc.dupe(u8, result.session_id) catch return,
            .model = alloc.dupe(u8, result.model) catch return,
        } }) catch {};
    }
};

fn freeEvent(event: Event) void {
    switch (event) {
        .text, .diagnostic, .failed => |value| alloc.free(value),
        .tool => |call| {
            alloc.free(call.name);
            alloc.free(call.status);
            alloc.free(call.output);
        },
        .done => |done| {
            alloc.free(done.session_id);
            alloc.free(done.model);
        },
    }
}
