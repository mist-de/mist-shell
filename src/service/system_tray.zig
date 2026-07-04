const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("basu/sd-bus.h");
});

const log = std.log.scoped(.system_tray);

pub const TrayItem = struct {
    service: []const u8 = "",
    icon_name: []const u8 = "",
    title: []const u8 = "",
    status: []const u8 = "",
    category: []const u8 = "",
    id: []const u8 = "",
};

pub const State = struct {
    available: bool = false,
    items: [8]TrayItem = undefined,
    item_count: usize = 0,
};

var bus: ?*c.sd_bus = null;
pub var state: State = .{};

pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator;
    var b: ?*c.sd_bus = null;
    if (c.sd_bus_open_user(&b) < 0) {
        log.warn("no session bus for system tray", .{});
        return;
    }
    bus = b;

    _ = c.sd_bus_request_name(b.?, "org.kde.StatusNotifierHost-7361746F72696E656C", 0);
    state.available = true;

    registerHost();
    enumerateItems();
    log.info("system tray initialized", .{});
}

fn registerHost() void {
    const b2 = bus orelse return;
    const host_name = "org.kde.StatusNotifierHost-7361746F72696E656C";
    _ = c.sd_bus_call_method(b2, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierHost", null, null, "s", host_name);
}

fn enumerateItems() void {
    const b2 = bus orelse return;
    var reply: ?*c.sd_bus_message = null;
    if (c.sd_bus_call_method(b2, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.freedesktop.DBus.Properties", "Get", null, &reply, "ss", "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems") < 0) return;
    defer _ = c.sd_bus_message_unref(reply);

    if (c.sd_bus_message_enter_container(reply, 'v', "as") >= 0) {
        var item: [*:0]u8 = undefined;
        while (c.sd_bus_message_read(reply, "s", &item) > 0) {
            addItem(std.mem.span(item));
        }
        _ = c.sd_bus_message_exit_container(reply);
    }
}

fn addItem(service: []const u8) void {
    if (state.item_count >= state.items.len) return;
    const duped_svc = std.heap.page_allocator.dupe(u8, service) catch return;
    state.items[state.item_count] = .{ .service = duped_svc };
    const idx = state.item_count;
    state.item_count += 1;
    refreshItem(idx);
}

fn refreshItem(idx: usize) void {
    const b2 = bus orelse return;
    if (idx >= state.item_count) return;
    const item = &state.items[idx];

    var reply: ?*c.sd_bus_message = null;

    if (c.sd_bus_call_method(b2, item.service.ptr, "/StatusNotifierItem", "org.freedesktop.DBus.Properties", "Get", null, &reply, "ss", "org.kde.StatusNotifierItem", "IconName") >= 0) {
        if (c.sd_bus_message_enter_container(reply, 'v', "s") >= 0) {
            var val: [*:0]u8 = undefined;
            if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                item.icon_name = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_unref(reply);
        reply = null;
    }

    if (c.sd_bus_call_method(b2, item.service.ptr, "/StatusNotifierItem", "org.freedesktop.DBus.Properties", "Get", null, &reply, "ss", "org.kde.StatusNotifierItem", "Title") >= 0) {
        if (c.sd_bus_message_enter_container(reply, 'v', "s") >= 0) {
            var val: [*:0]u8 = undefined;
            if (c.sd_bus_message_read(reply, "s", &val) > 0) {
                item.title = std.heap.page_allocator.dupe(u8, std.mem.span(val)) catch "";
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_unref(reply);
        reply = null;
    }
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
    if (bus) |b2| {
        _ = c.sd_bus_close(b2);
        _ = c.sd_bus_unref(b2);
        bus = null;
    }
    for (state.items[0..state.item_count]) |*item| {
        if (item.service.len > 0) std.heap.page_allocator.free(@constCast(item.service));
        if (item.icon_name.len > 0) std.heap.page_allocator.free(@constCast(item.icon_name));
        if (item.title.len > 0) std.heap.page_allocator.free(@constCast(item.title));
        if (item.status.len > 0) std.heap.page_allocator.free(@constCast(item.status));
        if (item.category.len > 0) std.heap.page_allocator.free(@constCast(item.category));
        if (item.id.len > 0) std.heap.page_allocator.free(@constCast(item.id));
    }
}
