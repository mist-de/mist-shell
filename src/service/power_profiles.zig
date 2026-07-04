const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("basu/sd-bus.h");
});

const log = std.log.scoped(.power_profiles);

pub const State = struct {
    available: bool = false,
    active_profile: []const u8 = "",
};

var bus: ?*c.sd_bus = null;
pub var state: State = .{};

pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator;
    var b: ?*c.sd_bus = null;
    if (c.sd_bus_open_system(&b) < 0) {
        log.debug("no system bus for power profiles", .{});
        return;
    }
    bus = b;
    refresh();
    state.available = if (state.active_profile.len > 0) true else false;
    log.info("power profiles initialized", .{});
}

pub fn refresh() void {
    const b2 = bus orelse return;

    var reply: ?*c.sd_bus_message = null;
    if (c.sd_bus_call_method(b2, "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "org.freedesktop.DBus.Properties", "Get", null, &reply, "ss", "net.hadess.PowerProfiles", "ActiveProfile") >= 0) {
        if (c.sd_bus_message_enter_container(reply, 'v', "s") >= 0) {
            var val: [*:0]u8 = undefined;
            if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                state.active_profile = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_unref(reply);
        reply = null;
    }
}

pub fn setActive(name: []const u8) void {
    const b2 = bus orelse return;
    _ = c.sd_bus_call_method(b2, "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "SetProfile", null, null, "s", name.ptr);
    state.active_profile = std.heap.page_allocator.dupe(u8, name) catch "";
}

pub fn process() void {
    const b2 = bus orelse return;
    _ = c.sd_bus_process(b2, null);
}

pub fn getFd() posix.fd_t {
    const b2 = bus orelse return -1;
    return c.sd_bus_get_fd(b2);
}

pub fn deinit() void {
    if (bus) |b| {
        _ = c.sd_bus_close(b);
        _ = c.sd_bus_unref(b);
        bus = null;
    }
    if (state.active_profile.len > 0) std.heap.page_allocator.free(@constCast(state.active_profile));
}
