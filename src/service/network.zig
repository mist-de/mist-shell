const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("basu/sd-bus.h");
});

const log = std.log.scoped(.network);

pub const DeviceType = enum(u32) {
    unknown = 0,
    ethernet = 1,
    wifi = 2,
    bt = 5,
    _,
};

pub const DeviceInfo = struct {
    name: []const u8 = "",
    dev_type: DeviceType = .unknown,
    state: u32 = 0,
    strength: u8 = 0,
    ssid: []const u8 = "",
};

pub const State = struct {
    available: bool = false,
    connectivity: u32 = 0,
    devices: [4]DeviceInfo = undefined,
    device_count: usize = 0,
};

var bus: ?*c.sd_bus = null;
pub var state: State = .{};

pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator;
    var b: ?*c.sd_bus = null;
    if (c.sd_bus_open_system(&b) < 0) {
        log.warn("failed to open system bus", .{});
        return;
    }
    bus = b;
    refresh();
    state.available = true;
    log.info("NetworkManager initialized", .{});
}

pub fn refresh() void {
    const b = bus orelse return;

    var reply: ?*c.sd_bus_message = null;
    if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.DBus.Properties", "Get", null, &reply, "ss", "org.freedesktop.NetworkManager", "Connectivity") >= 0) {
        if (c.sd_bus_message_enter_container(reply, 'v', "u") >= 0) {
            var conn: u32 = 0;
            if (c.sd_bus_message_read(reply, "u", &conn) >= 0) {
                state.connectivity = conn;
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_unref(reply);
        reply = null;
    }

    if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager", "GetAllDevices", null, &reply, null) >= 0) {
        if (c.sd_bus_message_enter_container(reply, 'a', "o") >= 0) {
            var dev_path: [*:0]u8 = undefined;
            while (c.sd_bus_message_read(reply, "o", &dev_path) > 0) {
                if (state.device_count >= state.devices.len) break;
                const idx = state.device_count;
                state.device_count += 1;
                var d = &state.devices[idx];
                var d_reply: ?*c.sd_bus_message = null;

                if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", dev_path, "org.freedesktop.DBus.Properties", "Get", null, &d_reply, "ss", "org.freedesktop.NetworkManager.Device", "Interface") >= 0) {
                    if (c.sd_bus_message_enter_container(d_reply, 'v', "s") >= 0) {
                        var val: [*:0]u8 = undefined;
                        if (c.sd_bus_message_read(d_reply, "s", &val) > 0) {
                            d.name = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
                        }
                        _ = c.sd_bus_message_exit_container(d_reply);
                    }
                    _ = c.sd_bus_message_unref(d_reply);
                    d_reply = null;
                }

                if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", dev_path, "org.freedesktop.DBus.Properties", "Get", null, &d_reply, "ss", "org.freedesktop.NetworkManager.Device", "DeviceType") >= 0) {
                    if (c.sd_bus_message_enter_container(d_reply, 'v', "u") >= 0) {
                        var dt: u32 = 0;
                        if (c.sd_bus_message_read(d_reply, "u", &dt) > 0) {
                            d.dev_type = @enumFromInt(dt);
                        }
                        _ = c.sd_bus_message_exit_container(d_reply);
                    }
                    _ = c.sd_bus_message_unref(d_reply);
                    d_reply = null;
                }

                if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", dev_path, "org.freedesktop.DBus.Properties", "Get", null, &d_reply, "ss", "org.freedesktop.NetworkManager.Device", "State") >= 0) {
                    if (c.sd_bus_message_enter_container(d_reply, 'v', "u") >= 0) {
                        var st: u32 = 0;
                        if (c.sd_bus_message_read(d_reply, "u", &st) > 0) {
                            d.state = st;
                        }
                        _ = c.sd_bus_message_exit_container(d_reply);
                    }
                    _ = c.sd_bus_message_unref(d_reply);
                    d_reply = null;
                }

                if (d.dev_type == .wifi) {
                    if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", dev_path, "org.freedesktop.DBus.Properties", "Get", null, &d_reply, "ss", "org.freedesktop.NetworkManager.Device.Wireless", "ActiveAccessPoint") >= 0) {
                        if (c.sd_bus_message_enter_container(d_reply, 'v', "o") >= 0) {
                            var ap_path: [*:0]u8 = undefined;
                            if (c.sd_bus_message_read(d_reply, "o", &ap_path) > 0) {
                                const ap = std.mem.span(ap_path);
                                var ap_reply: ?*c.sd_bus_message = null;
                                _ = c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", ap, "org.freedesktop.DBus.Properties", "GetAll", null, &ap_reply, "s", "org.freedesktop.NetworkManager.AccessPoint");
                                if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", ap, "org.freedesktop.DBus.Properties", "Get", null, &ap_reply, "ss", "org.freedesktop.NetworkManager.AccessPoint", "Strength") >= 0) {
                                    if (c.sd_bus_message_enter_container(ap_reply, 'v', "y") >= 0) {
                                        var strength: u8 = 0;
                                        if (c.sd_bus_message_read(ap_reply, "y", &strength) > 0) {
                                            d.strength = strength;
                                        }
                                        _ = c.sd_bus_message_exit_container(ap_reply);
                                    }
                                    _ = c.sd_bus_message_unref(ap_reply);
                                    ap_reply = null;
                                }
                                if (c.sd_bus_call_method(b, "org.freedesktop.NetworkManager", ap, "org.freedesktop.DBus.Properties", "Get", null, &ap_reply, "ss", "org.freedesktop.NetworkManager.AccessPoint", "Ssid") >= 0) {
                                    if (c.sd_bus_message_enter_container(ap_reply, 'v', "s") >= 0) {
                                        var raw: [*:0]u8 = undefined;
                                        if (c.sd_bus_message_read(ap_reply, "s", &raw) > 0) {
                                            d.ssid = std.heap.page_allocator.dupe(u8, std.mem.span(raw)) catch "";
                                        }
                                        _ = c.sd_bus_message_exit_container(ap_reply);
                                    }
                                    _ = c.sd_bus_message_unref(ap_reply);
                                    ap_reply = null;
                                }
                            }
                            _ = c.sd_bus_message_exit_container(d_reply);
                        }
                        _ = c.sd_bus_message_unref(d_reply);
                        d_reply = null;
                    }
                }
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_unref(reply);
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
    for (state.devices[0..state.device_count]) |*d| {
        if (d.name.len > 0) std.heap.page_allocator.free(@constCast(d.name));
        if (d.ssid.len > 0) std.heap.page_allocator.free(@constCast(d.ssid));
    }
}
