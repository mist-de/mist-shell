const std = @import("std");

const c = @cImport({
    @cInclude("basu/sd-bus.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

const log = std.log.scoped(.sysinfo);

pub const State = struct {
    available: bool = false,
    cpu_percent: u8 = 0,
    mem_percent: u8 = 0,
    mem_total_mb: u32 = 0,
    mem_used_mb: u32 = 0,
    temp_celsius: f32 = 0,
};

pub var state: State = .{};
var prev_idle: u64 = 0;
var prev_total: u64 = 0;
var tick: u64 = 0;

pub fn init() void {
    state.available = true;
    log.info("SysInfo initialized", .{});
}

pub fn refresh() void {
    readCpu();
    readMem();
    readTemp();
}

fn readCpu() void {
    var buf: [4096]u8 = undefined;
    const fd = c.open("/proc/stat", 0);
    if (fd < 0) return;
    defer _ = c.close(fd);
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return;
    const content = buf[0..@as(usize, @intCast(n))];

    var lines = std.mem.splitScalar(u8, content, '\n');
    const first = lines.next() orelse return;
    if (first.len < 4 or !std.mem.eql(u8, first[0..3], "cpu")) return;

    var fields = std.mem.splitScalar(u8, first[5..], ' ');
    var vals: [10]u64 = .{0} ** 10;
    var i: usize = 0;
    while (fields.next()) |f| {
        const trimmed = std.mem.trim(u8, f, " \t");
        if (trimmed.len == 0) continue;
        if (i >= vals.len) break;
        vals[i] = std.fmt.parseInt(u64, trimmed, 10) catch 0;
        i += 1;
    }
    if (i < 4) return;

    const total = vals[0] + vals[1] + vals[2] + vals[3] + vals[4] + vals[5] + vals[6] + vals[7] + vals[8];
    const idle = vals[3];

    if (prev_total > 0 and prev_idle > 0) {
        const total_delta = total -| prev_total;
        const idle_delta = idle -| prev_idle;
        if (total_delta > 0) {
            state.cpu_percent = @intCast(@min(100, (total_delta - idle_delta) * 100 / total_delta));
        }
    }

    prev_total = total;
    prev_idle = idle;
}

fn readMem() void {
    var buf: [4096]u8 = undefined;
    const fd = c.open("/proc/meminfo", 0);
    if (fd < 0) return;
    defer _ = c.close(fd);
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return;
    const content = buf[0..@as(usize, @intCast(n))];

    var total_kb: u64 = 0;
    var avail_kb: u64 = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            total_kb = extractInt(line);
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            avail_kb = extractInt(line);
        }
    }

    if (total_kb > 0 and avail_kb > 0) {
        state.mem_total_mb = @intCast(total_kb / 1024);
        const used_kb = total_kb -| avail_kb;
        state.mem_used_mb = @intCast(used_kb / 1024);
        state.mem_percent = @intCast(@min(100, used_kb * 100 / total_kb));
    }
}

fn readTemp() void {
    var buf: [64]u8 = undefined;
    const fd = c.open("/sys/class/thermal/thermal_zone0/temp", 0);
    if (fd < 0) return;
    defer _ = c.close(fd);
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return;
    const s = std.mem.trim(u8, buf[0..@as(usize, @intCast(n))], " \n\r");
    const milli = std.fmt.parseInt(u32, s, 10) catch return;
    state.temp_celsius = @as(f32, @floatFromInt(milli)) / 1000.0;
}

pub fn poll() void {
    tick += 1;
    if (tick % 20 == 0) refresh();
}

fn extractInt(line: []const u8) u64 {
    var i: usize = 0;
    while (i < line.len and !std.ascii.isDigit(line[i])) {
        i += 1;
    }
    if (i >= line.len) return 0;
    const num_start = i;
    while (i < line.len and std.ascii.isDigit(line[i])) {
        i += 1;
    }
    return std.fmt.parseInt(u64, line[num_start..i], 10) catch 0;
}

pub fn getFd() posix.fd_t {
    _ = c; // keep cImport alive
    return -1;
}

const posix = std.posix;

pub fn process() void {}

pub fn deinit() void {}
