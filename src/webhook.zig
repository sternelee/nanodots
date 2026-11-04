//! A minimal GitHub webhook receiver — Rerun's inbound-trigger pattern
//! adapted for a desktop app. Listens on 127.0.0.1, accepts POSTs to
//! /hook/<token>, optionally verifies X-Hub-Signature-256 against a secret,
//! and queues events for the UI thread (drained once a second by the watch
//! scheduler tick, so no timers are armed from this thread).
const std = @import("std");
const engine = @import("fx");

pub const alloc = std.heap.c_allocator;

/// One accepted (or rejected) delivery, moved to the UI thread.
pub const Event = struct {
    /// X-GitHub-Event: "pull_request" / "issues" / "ping" / …
    kind: []u8,
    /// Payload "action", "ping" for the connectivity probe.
    action: []u8,
    /// repository.full_name, "" when the payload has none.
    repo: []u8,
    /// PR/issue number, 0 when not applicable.
    number: u32,
    /// PR/issue title or release name, for the event line.
    title: []u8,
    /// Signature check outcome (true when no secret is configured).
    verified: bool,
    /// Why the delivery was rejected (wrong path, bad signature, …); the
    /// event is still recorded, with this as its title.
    reject: []u8,
};

pub fn freeEvent(e: Event) void {
    alloc.free(e.kind);
    alloc.free(e.action);
    alloc.free(e.repo);
    alloc.free(e.title);
    alloc.free(e.reject);
}

const max_request: usize = 256 * 1024;

pub const Server = struct {
    port: u16,
    token: []u8,
    secret: []u8,
    net_server: ?std.Io.net.Server = null,
    thread: ?std.Thread = null,
    stopping: std.atomic.Value(bool) = .init(false),
    mutex: std.Io.Mutex = .init,
    queue: std.ArrayList(Event) = .empty,

    fn lock(self: *Server) void {
        self.mutex.lockUncancelable(engine.shared_io.getIo());
    }

    fn unlock(self: *Server) void {
        self.mutex.unlock(engine.shared_io.getIo());
    }

    pub fn create(port: u16, token: []const u8, secret: []const u8) !*Server {
        const self = try alloc.create(Server);
        errdefer alloc.destroy(self);
        self.* = .{
            .port = port,
            .token = try alloc.dupe(u8, token),
            .secret = try alloc.dupe(u8, secret),
        };
        return self;
    }

    pub fn start(self: *Server) !void {
        const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", self.port);
        self.net_server = try addr.listen(engine.shared_io.getIo(), .{ .reuse_address = true });
        self.thread = try std.Thread.spawn(.{}, serve, .{self});
    }

    pub fn stop(self: *Server) void {
        self.stopping.store(true, .release);
        if (self.net_server) |*server| {
            server.socket.close(engine.shared_io.getIo());
            self.net_server = null;
            // Wake a blocked accept in case the close didn't.
            if (std.Io.net.IpAddress.parseIp4("127.0.0.1", self.port)) |addr| {
                if (addr.connect(engine.shared_io.getIo(), .{ .mode = .stream })) |stream| {
                    var s = stream;
                    s.close(engine.shared_io.getIo());
                } else |_| {}
            } else |_| {}
        }
        if (self.thread) |t| t.join();
        self.thread = null;
        self.lock();
        for (self.queue.items) |e| freeEvent(e);
        self.queue.deinit(alloc);
        self.unlock();
        alloc.free(self.token);
        alloc.free(self.secret);
        alloc.destroy(self);
    }

    /// Pop the oldest queued event, if any. Called on the UI thread.
    pub fn pop(self: *Server) ?Event {
        self.lock();
        defer self.unlock();
        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);
    }

    fn enqueue(self: *Server, e: Event) void {
        self.lock();
        defer self.unlock();
        // Drop the oldest under sustained bursts; GitHub retries otherwise.
        if (self.queue.items.len >= 32) {
            const dropped = self.queue.orderedRemove(0);
            freeEvent(dropped);
        }
        self.queue.append(alloc, e) catch freeEvent(e);
    }

    fn serve(self: *Server) void {
        const io = engine.shared_io.getIo();
        while (!self.stopping.load(.acquire)) {
            var server = self.net_server orelse return;
            var stream = server.accept(io) catch return;
            defer stream.close(io);
            self.handle(&stream);
        }
    }

    fn handle(self: *Server, stream: *std.Io.net.Stream) void {
        const io = engine.shared_io.getIo();
        var buf = alloc.alloc(u8, max_request) catch return;
        defer alloc.free(buf);
        var scratch: [4096]u8 = undefined;
        var reader = stream.reader(io, &scratch);
        var len: usize = 0;
        while (len < buf.len) {
            var chunks = [_][]u8{buf[len..]};
            const n = reader.interface.readVec(&chunks) catch return;
            if (n == 0) break;
            len += n;
            if (requestComplete(buf[0..len])) break;
        }
        const req = buf[0..len];
        const ok = self.process(req);
        const response = if (ok)
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 14\r\nConnection: close\r\n\r\n{\"ok\":true}\n\n"
        else
            "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{\"error\":\"no\"}\n\n";
        var wbuf: [256]u8 = undefined;
        var w = stream.writer(io, &wbuf);
        w.interface.writeAll(response) catch {};
        w.interface.flush() catch {};
    }

    /// Returns true when the delivery was accepted.
    fn process(self: *Server, req: []const u8) bool {
        const head_end = std.mem.indexOf(u8, req, "\r\n\r\n") orelse return false;
        const head = req[0..head_end];
        const body = req[@min(head_end + 4, req.len)..];

        var lines = std.mem.splitScalar(u8, head, '\n');
        const request_line = std.mem.trimEnd(u8, lines.next() orelse return false, "\r");
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return false;
        const path = parts.next() orelse return false;
        if (!std.mem.eql(u8, method, "POST")) return false;
        const prefix = "/hook/";
        if (!std.mem.startsWith(u8, path, prefix)) return false;
        const given = path[prefix.len..];
        var query = std.mem.indexOfScalar(u8, given, '?') orelse given.len;
        _ = &query;
        if (!std.mem.eql(u8, given[0..query], self.token)) return false;

        var event_kind: []const u8 = "";
        var signature: ?[]const u8 = null;
        while (lines.next()) |line| {
            const trimmed = std.mem.trimEnd(u8, line, "\r");
            const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
            const name = std.mem.trim(u8, trimmed[0..colon], " \t");
            const value = std.mem.trim(u8, trimmed[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "X-GitHub-Event")) {
                event_kind = value;
            } else if (std.ascii.eqlIgnoreCase(name, "X-Hub-Signature-256")) {
                signature = value;
            }
        }

        const verified = self.verify(body, signature);
        const accepted = verified;
        var e = parseEvent(event_kind, body, verified);
        if (!accepted) {
            alloc.free(e.reject);
            e.reject = alloc.dupe(u8, "验签失败") catch &.{};
        }
        self.enqueue(e);
        return accepted;
    }

    fn verify(self: *Server, body: []const u8, signature: ?[]const u8) bool {
        if (self.secret.len == 0) return true;
        const sig = signature orelse return false;
        const hex_part = if (std.mem.startsWith(u8, sig, "sha256=")) sig[7..] else return false;
        if (hex_part.len != 64) return false;
        var mac = std.crypto.auth.hmac.sha2.HmacSha256.init(self.secret);
        mac.update(body);
        var digest: [32]u8 = undefined;
        mac.final(&digest);
        const expected = std.fmt.bytesToHex(digest, .lower);
        return std.crypto.timing_safe.eql([64]u8, expected, hex_part[0..64].*);
    }
};

fn requestComplete(req: []const u8) bool {
    const head_end = std.mem.indexOf(u8, req, "\r\n\r\n") orelse return false;
    var lines = std.mem.splitScalar(u8, req[0..head_end], '\n');
    _ = lines.next();
    var content_length: usize = 0;
    while (lines.next()) |line| {
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, trimmed[0..colon], " \t"), "Content-Length")) {
            content_length = std.fmt.parseInt(usize, std.mem.trim(u8, trimmed[colon + 1 ..], " \t"), 10) catch 0;
        }
    }
    return req.len >= head_end + 4 + content_length;
}

fn dupeOrEmpty(s: []const u8) []u8 {
    return alloc.dupe(u8, s) catch &.{};
}

fn parseEvent(kind: []const u8, body: []const u8, verified: bool) Event {
    var action: []const u8 = "";
    var repo: []const u8 = "";
    var number: u32 = 0;
    var title: []const u8 = "";

    var parsed = std.json.parseFromSlice(std.json.Value, alloc, body, .{}) catch {
        return .{
            .kind = dupeOrEmpty(kind),
            .action = if (std.mem.eql(u8, kind, "ping")) dupeOrEmpty("ping") else &.{},
            .repo = &.{},
            .number = 0,
            .title = &.{},
            .verified = verified,
            .reject = dupeOrEmpty("JSON 解析失败"),
        };
    };
    defer parsed.deinit();
    if (parsed.value == .object) {
        const obj = parsed.value.object;
        if (obj.get("action")) |v| {
            if (v == .string) action = v.string;
        }
        if (obj.get("repository")) |v| {
            if (v == .object) {
                if (v.object.get("full_name")) |n| {
                    if (n == .string) repo = n.string;
                }
            }
        }
        for ([_][]const u8{ "issue", "pull_request" }) |key| {
            if (obj.get(key)) |v| {
                if (v == .object) {
                    if (v.object.get("number")) |n| {
                        if (n == .integer) number = @intCast(@max(0, @min(1_000_000_000, n.integer)));
                    }
                    if (v.object.get("title")) |t| {
                        if (t == .string) title = t.string;
                    }
                    break;
                }
            }
        }
    }

    return .{
        .kind = dupeOrEmpty(kind),
        .action = dupeOrEmpty(if (std.mem.eql(u8, kind, "ping")) "ping" else action),
        .repo = dupeOrEmpty(repo),
        .number = number,
        .title = dupeOrEmpty(title),
        .verified = verified,
        .reject = &.{},
    };
}
