const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("basu/sd-bus.h");
});

const log = std.log.scoped(.mpris);

pub const PlayerInfo = struct {
    bus_name: []const u8 = "",
    identity: []const u8 = "",
    playback_status: enum { stopped, playing, paused, unknown } = .unknown,
    track_title: []const u8 = "",
    track_artist: []const u8 = "",
    track_id: []const u8 = "",
    position_usec: i64 = 0,
    length_usec: i64 = 0,
    art_url: []const u8 = "",
    can_play: bool = false,
    can_pause: bool = false,
    can_go_next: bool = false,
    can_go_prev: bool = false,
};

pub const State = struct {
    available: bool = false,
    players: [4]PlayerInfo = undefined,
    player_count: usize = 0,
    active_idx: usize = 0,
};

var bus: ?*c.sd_bus = null;
pub var state: State = .{};

pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator;
    var b: ?*c.sd_bus = null;
    if (c.sd_bus_open_user(&b) < 0) {
        log.warn("failed to open session bus", .{});
        return;
    }
    bus = b;

    if (c.sd_bus_call_method(b.?, "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "ListNames", null, null, null) >= 0) {
        enumeratePlayers(b.?);
    }
    state.available = state.player_count > 0;
    log.info("found {} MPRIS player(s)", .{state.player_count});
}

fn enumeratePlayers(b: *c.sd_bus) void {
    var reply: ?*c.sd_bus_message = null;
    if (c.sd_bus_call_method(b, "org.freedesktop.DBus", "/", "org.freedesktop.DBus", "ListNames", null, &reply, null) < 0) return;
    defer _ = c.sd_bus_message_unref(reply);

    if (c.sd_bus_message_enter_container(reply, 'a', "s") < 0) return;
    var name: [*:0]u8 = undefined;
    while (c.sd_bus_message_read(reply, "s", &name) > 0) {
        const n = std.mem.span(name);
        if (std.mem.indexOf(u8, n, "org.mpris.MediaPlayer2.") != null) {
            addPlayer(b, n);
        }
    }
}

fn addPlayer(b: *c.sd_bus, name: []const u8) void {
    if (state.player_count >= state.players.len) return;
    const duped = std.heap.page_allocator.dupe(u8, name) catch return;
    state.players[state.player_count] = .{ .bus_name = duped };
    const idx = state.player_count;
    state.player_count += 1;
    refreshPlayer(b, idx);
}

fn refreshPlayer(b: *c.sd_bus, idx: usize) void {
    const p = &state.players[idx];
    if (p.bus_name.len == 0) return;

    var reply: ?*c.sd_bus_message = null;
    if (c.sd_bus_call_method(b, p.bus_name.ptr, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "GetAll", null, &reply, "s", "org.mpris.MediaPlayer2.Player") < 0) return;
    defer _ = c.sd_bus_message_unref(reply);

    // Reuse reply for individual property gets
    if (c.sd_bus_call_method(b, p.bus_name.ptr, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "Get", null, &reply, "ss", "org.mpris.MediaPlayer2.Player", "PlaybackStatus") >= 0) {
        var val: [*:0]u8 = undefined;
        if (c.sd_bus_message_enter_container(reply, 'v', "s") >= 0) {
            if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                const s = std.mem.span(val);
                p.playback_status = if (std.mem.eql(u8, s, "Playing")) .playing else if (std.mem.eql(u8, s, "Paused")) .paused else .stopped;
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_unref(reply);
        reply = null;
    }

    if (c.sd_bus_call_method(b, p.bus_name.ptr, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "Get", null, &reply, "ss", "org.mpris.MediaPlayer2.Player", "Metadata") >= 0) {
        if (c.sd_bus_message_enter_container(reply, 'v', "a{sv}") >= 0) {
            if (c.sd_bus_message_enter_container(reply, 'a', "{sv}") >= 0) {
                var key: [*:0]u8 = undefined;
                while (c.sd_bus_message_enter_container(reply, 'e', "sv") > 0) {
                    _ = c.sd_bus_message_read(reply, "s", &key);
                    const k = std.mem.span(key);
                    if (c.sd_bus_message_enter_container(reply, 'v', null) >= 0) {
                        if (std.mem.eql(u8, k, "xesam:title")) {
                            var val: [*:0]u8 = undefined;
                            if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                                p.track_title = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
                            }
                        } else if (std.mem.eql(u8, k, "xesam:artist")) {
                            if (c.sd_bus_message_enter_container(reply, 'a', "s") >= 0) {
                                var val: [*:0]u8 = undefined;
                                if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                                    p.track_artist = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
                                }
                                _ = c.sd_bus_message_exit_container(reply);
                            }
                        } else if (std.mem.eql(u8, k, "mpris:artUrl")) {
                            var val: [*:0]u8 = undefined;
                            if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                                p.art_url = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
                            }
                        } else if (std.mem.eql(u8, k, "mpris:trackid")) {
                            var val: [*:0]u8 = undefined;
                            if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                                p.track_id = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
                            }
                        } else if (std.mem.eql(u8, k, "mpris:length")) {
                            var val: u64 = 0;
                            if (c.sd_bus_message_read(reply, "t", &val) > 0) {
                                p.length_usec = @intCast(val);
                            }
                        }
                        _ = c.sd_bus_message_exit_container(reply);
                    }
                    _ = c.sd_bus_message_exit_container(reply);
                }
                _ = c.sd_bus_message_exit_container(reply);
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_unref(reply);
        reply = null;
    }
}

pub fn process() void {
    const b = bus orelse return;
    _ = c.sd_bus_process(b, null);
}

pub fn getFd() posix.fd_t {
    const b = bus orelse return -1;
    return c.sd_bus_get_fd(b);
}

pub fn deinit() void {
    if (bus) |b| {
        _ = c.sd_bus_close(b);
        _ = c.sd_bus_unref(b);
        bus = null;
    }
    for (state.players[0..state.player_count]) |*p| {
        if (p.bus_name.len > 0) std.heap.page_allocator.free(@constCast(p.bus_name));
        if (p.track_title.len > 0) std.heap.page_allocator.free(@constCast(p.track_title));
        if (p.track_artist.len > 0) std.heap.page_allocator.free(@constCast(p.track_artist));
        if (p.art_url.len > 0) std.heap.page_allocator.free(@constCast(p.art_url));
        if (p.track_id.len > 0) std.heap.page_allocator.free(@constCast(p.track_id));
    }
}
