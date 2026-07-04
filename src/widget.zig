const std = @import("std");
const rdr = @import("shell/render.zig");
const text = @import("shell/render/text.zig");

pub const Spacer = struct {
    width: u32 = 8,
    pub fn init() Spacer { return .{}; }
    pub fn deinit(_: *Spacer) void {}
    pub fn measure(_: *Spacer, _: u32, _: u32) u32 { return 0; }
    pub fn put(_: *Spacer, _: *rdr.Surface, _: i32, _: i32, _: u32, _: u32) void {}
};

pub const Separator = struct {
    width: u32 = 2,
    pub fn init() Separator { return .{}; }
    pub fn deinit(_: *Separator) void {}
    pub fn measure(_: *Separator, _: u32, _: u32) u32 { return 0; }
    pub fn put(self: *Separator, surface: *rdr.Surface, x: i32, y: i32, _: u32, h: u32) void {
        _ = self;
        surface.fillRect(x, y + 4, 2, h - 8, .{ .r = 0x31, .g = 0x32, .b = 0x44, .a = 0xff });
    }
};

pub const Clock = struct {
    font: *text.Font,
    color: rdr.Color = .{ .r = 0xcd, .g = 0xd6, .b = 0xf4, .a = 0xff },
    buf: [32]u8 = undefined,

    pub fn init(font: *text.Font) Clock { return .{ .font = font }; }
    pub fn deinit(_: *Clock) void {}

    pub fn measure(self: *Clock, _: u32, _: u32) u32 {
        return self.font.measureText(self.formatTime()) + 16;
    }

    pub fn put(self: *Clock, surface: *rdr.Surface, x: i32, _: i32, _: u32, h: u32) void {
        const time = self.formatTime();
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 4);
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, time, x + 8, ty, self.color);
    }

    pub fn formatTime(self: *Clock) []const u8 {
        const now = unixTime();
        if (now <= 0) return "??:??";
        const tm = extern struct { sec: i32, min: i32, hour: i32, mday: i32, mon: i32, year: i32, wday: i32, yday: i32, isdst: i32 };
        var result: tm = undefined;
        const c = struct { extern "c" fn localtime_r(timep: *const i64, result: *tm) ?*tm; };
        var t = now;
        if (c.localtime_r(&t, &result) == null) return "??:??";
        return std.fmt.bufPrint(&self.buf, "{d:0>2}:{d:0>2}", .{ @as(u8, @intCast(result.hour)), @as(u8, @intCast(result.min)) }) catch "??:??";
    }
};

fn unixTime() i64 {
    const ts = extern struct { sec: i64, nsec: i64 };
    const c = struct { extern "c" fn clock_gettime(clock_id: c_int, tp: *ts) c_int; };
    var t: ts = undefined;
    return if (c.clock_gettime(0, &t) == 0) t.sec else 0;
}

pub const Workspace = struct {
    tags: std.ArrayListUnmanaged(u32) = .{ .items = &.{}, .capacity = 0 },
    focused: u32 = 0,

    pub fn init() Workspace { return .{}; }
    pub fn deinit(self: *Workspace) void { self.tags.deinit(std.heap.page_allocator); }

    pub fn measure(self: *Workspace, _: u32, _: u32) u32 {
        return @as(u32, @intCast(self.tags.items.len)) * 28;
    }

    pub fn put(self: *Workspace, surface: *rdr.Surface, x: i32, y: i32, _: u32, h: u32) void {
        var cx = x;
        for (self.tags.items) |tag| {
            const active = tag == self.focused;
            const color: rdr.Color = if (active) .{ .r = 0x89, .g = 0xb4, .b = 0xfa, .a = 0xff } else .{ .r = 0x56, .g = 0x5f, .b = 0x89, .a = 0xff };
            surface.fillRect(cx, y + 8, 20, h - 16, color);
            cx += 26;
        }
    }
};

pub const Battery = struct {
    capacity: u8 = 0,
    charging: bool = false,
    font: ?*text.Font,

    pub fn init(font: ?*text.Font) Battery { return .{ .font = font }; }
    pub fn deinit(_: *Battery) void {}

    pub fn poll(self: *Battery) void {
        self.capacity = readSysfsInt("/sys/class/power_supply/BAT0/capacity", 0);
        const status = readSysfsStr("/sys/class/power_supply/BAT0/status");
        self.charging = std.mem.eql(u8, status, "Charging") or std.mem.eql(u8, status, "Full");
    }

    pub fn measure(self: *Battery, _: u32, _: u32) u32 {
        _ = self;
        return 0;
    }

    pub fn put(self: *Battery, surface: *rdr.Surface, x: i32, y: i32, _: u32, h: u32) void {
        const fg = self.fgColor();
        const bx = x + 4;
        const by = y + 8;
        const bw: u32 = 32;
        const bh: u32 = h - 16;
        surface.fillRect(bx, by, bw, bh, fg);
        const fill = if (self.capacity > 0) @max(1, bw * self.capacity / 100) else 0;
        if (fill > 0) surface.fillRect(bx + 1, by + 1, fill - 2, bh - 2, fg);
    }

    fn fgColor(self: *Battery) rdr.Color {
        if (self.charging) return .{ .r = 0x89, .g = 0xdc, .b = 0xeb, .a = 0xff };
        if (self.capacity < 15) return .{ .r = 0xf3, .g = 0x8b, .b = 0xa8, .a = 0xff };
        return .{ .r = 0xcd, .g = 0xd6, .b = 0xf4, .a = 0xff };
    }
};

fn readSysfsInt(path: [:0]const u8, default: u8) u8 {
    const c = struct { extern "c" fn open(path: [*:0]const u8, flags: c_int) c_int; extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize; extern "c" fn close(fd: c_int) c_int; };
    const fd = c.open(path, 0);
    if (fd < 0) return default;
    var buf: [16]u8 = undefined;
    const n = c.read(fd, &buf, buf.len);
    _ = c.close(fd);
    if (n <= 0) return default;
    return std.fmt.parseInt(u8, std.mem.trim(u8, buf[0..@as(usize, @intCast(n))], &[_]u8{'\n', ' '}), 10) catch default;
}

fn readSysfsStr(path: [:0]const u8) []const u8 {
    const c = struct { extern "c" fn open(path: [*:0]const u8, flags: c_int) c_int; extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize; extern "c" fn close(fd: c_int) c_int; };
    const fd = c.open(path, 0);
    if (fd < 0) return "";
    var buf: [32]u8 = undefined;
    const n = c.read(fd, &buf, buf.len);
    _ = c.close(fd);
    if (n <= 0) return "";
    return buf[0..@as(usize, @intCast(n))];
}

pub const Widget = union(enum) {
    spacer: Spacer,
    separator: Separator,
    clock: Clock,
    workspaces: Workspace,
    battery: Battery,

    pub fn measure(self: *Widget, max_w: u32, bar_h: u32) u32 {
        return switch (self.*) {
            .spacer => self.spacer.measure(max_w, bar_h),
            .separator => self.separator.measure(max_w, bar_h),
            .clock => self.clock.measure(max_w, bar_h),
            .workspaces => self.workspaces.measure(max_w, bar_h),
            .battery => self.battery.measure(max_w, bar_h),
        };
    }

    pub fn render(self: *Widget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        switch (self.*) {
            .spacer => self.spacer.put(surface, x, y, w, h),
            .separator => self.separator.put(surface, x, y, w, h),
            .clock => self.clock.put(surface, x, y, w, h),
            .workspaces => self.workspaces.put(surface, x, y, w, h),
            .battery => self.battery.put(surface, x, y, w, h),
        }
    }

    pub fn deinit(self: *Widget) void {
        switch (self.*) {
            .spacer => self.spacer.deinit(),
            .separator => self.separator.deinit(),
            .clock => self.clock.deinit(),
            .workspaces => self.workspaces.deinit(),
            .battery => self.battery.deinit(),
        }
    }
};
