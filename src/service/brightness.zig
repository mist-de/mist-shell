const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("basu/sd-bus.h");
    @cInclude("dirent.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

const log = std.log.scoped(.brightness);

pub const BacklightInfo = struct {
    name: []const u8 = "",
    brightness: u32 = 0,
    max_brightness: u32 = 0,
};

pub const State = struct {
    available: bool = false,
    backlights: [4]BacklightInfo = undefined,
    count: usize = 0,
};

pub var state: State = .{};

pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator;
    enumerateBacklights();
    state.available = state.count > 0;
    if (state.available) log.info("backlight initialized", .{});
}

fn enumerateBacklights() void {
    const dir = c.opendir("/sys/class/backlight");
    if (dir == null) return;
    defer _ = c.closedir(dir);

    while (true) {
        const entry = c.readdir(dir);
        if (entry == null) break;
        const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&entry.*.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (state.count >= state.backlights.len) break;

        state.backlights[state.count].name = std.heap.page_allocator.dupe(u8, name) catch "";

        const max_path = std.fmt.allocPrintSentinel(std.heap.page_allocator, "/sys/class/backlight/{s}/max_brightness", .{name}, 0) catch continue;
        defer std.heap.page_allocator.free(max_path);
        state.backlights[state.count].max_brightness = readIntFile(max_path);

        const bright_path = std.fmt.allocPrintSentinel(std.heap.page_allocator, "/sys/class/backlight/{s}/brightness", .{name}, 0) catch continue;
        defer std.heap.page_allocator.free(bright_path);
        state.backlights[state.count].brightness = readIntFile(bright_path);

        state.count += 1;
    }
}

fn readIntFile(path: [:0]const u8) u32 {
    var buf: [32]u8 = undefined;
    const fd = c.open(path.ptr, 0);
    if (fd < 0) return 0;
    defer _ = c.close(fd);
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return 0;
    const s = std.mem.trimEnd(u8, buf[0..@as(usize, @intCast(n))], " \n\r");
    return std.fmt.parseInt(u32, s, 10) catch 0;
}

pub fn refresh() void {
    if (state.count == 0) return;
    for (state.backlights[0..state.count]) |*bl| {
        const path = std.fmt.allocPrintSentinel(std.heap.page_allocator, "/sys/class/backlight/{s}/brightness", .{bl.name}, 0) catch continue;
        defer std.heap.page_allocator.free(path);
        bl.brightness = readIntFile(path);
    }
}

pub fn setBrightness(idx: usize, value: u32) void {
    if (idx >= state.count) return;
    const bl = &state.backlights[idx];
    const clamped = @min(value, bl.max_brightness);
    const path = std.fmt.allocPrintSentinel(std.heap.page_allocator, "/sys/class/backlight/{s}/brightness", .{bl.name}, 0) catch return;
    defer std.heap.page_allocator.free(path);
    const fd = c.open(path.ptr, 1);
    if (fd < 0) {
        log.warn("cannot write brightness for {s}", .{bl.name});
        return;
    }
    defer _ = c.close(fd);
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{clamped}) catch return;
    _ = c.write(fd, s.ptr, s.len);
    bl.brightness = clamped;
}

pub fn process() void {}
pub fn getFd() posix.fd_t { return -1; }
pub fn deinit() void {}
