const std = @import("std");
const rdr = @import("../shell/render.zig");
const text = @import("../shell/render/text.zig");
const theme = @import("../theme.zig");
const battery = @import("../service/battery.zig");
const volume = @import("../service/volume.zig");
const mpris = @import("../service/mpris.zig");
const network = @import("../service/network.zig");
const sysinfo = @import("../service/sysinfo.zig");
const brightness = @import("../service/brightness.zig");
const power_profiles = @import("../service/power_profiles.zig");
const system_tray = @import("../service/system_tray.zig");
const workspace = @import("../workspace.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.registry);

const Color = rdr.Color;
const t = &theme.default;

fn iconSize(h: u32) u32 {
    return @min(20, @max(@min(16, h), h * 9 / 16));
}

fn textSize(h: u32) u32 {
    return @min(15, @max(@min(12, h -| 2), h * 7 / 16));
}

fn edgePadding(h: u32) u32 {
    return @max(3, h / 8);
}

fn drawWidgetBg(surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
    const bg = t.panelColor(t.bar.item_background);
    if (bg.a > 0) {
        surface.fillRect(x, y, w, h, bg);
    }
}

pub const Spacer = struct {
    pub fn init() Spacer { return .{}; }
    pub fn deinit(_: *Spacer) void {}
    pub fn measure(_: *Spacer, _: u32, _: u32) u32 { return 0; }
    pub fn render(_: *Spacer, _: *rdr.Surface, _: i32, _: i32, _: u32, _: u32) void {}
};

pub const Separator = struct {
    width: u32 = 1,
    color: Color = t.colors.surface0,
    pub fn init() Separator { return .{}; }
    pub fn deinit(_: *Separator) void {}
    pub fn measure(self: *Separator, _: u32, h: u32) u32 { return self.width + edgePadding(h) * 2; }
    pub fn render(self: *Separator, surface: *rdr.Surface, x: i32, y: i32, _: u32, h: u32) void {
        const pad = edgePadding(h);
        surface.fillRect(x + @as(i32, @intCast(pad)), y + @as(i32, @intCast(h / 4)), self.width, h / 2, self.color);
    }
};

pub const TagWidget = struct {
    font: *text.Font,
    color_active: Color = t.colors.accent,
    color_inactive: Color = t.colors.accent,
    color_urgent: Color = t.colors.critical,
    color_active_text: Color = t.bar.item_active_text,
    color_inactive_text: Color = t.colors.accent,
    color_urgent_text: Color = t.colors.background,
    symbols: [9][:0]const u8 = .{ "1", "2", "3", "4", "5", "6", "7", "8", "9" },
    pub fn init(font: *text.Font) TagWidget {
        return .{ .font = font };
    }
    pub fn deinit(_: *TagWidget) void {}
    pub fn measure(_: *TagWidget, _: u32, _: u32) u32 {
        const n = workspace.tag_state.tag_count;
        return @as(u32, @intCast(n)) * 24 + @as(u32, @intCast(n)) * 4 + 8;
    }
    pub fn render(self: *TagWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        _ = w;
        const n = workspace.tag_state.tag_count;
        if (n == 0) return;
        var cx = x + @as(i32, @intCast(edgePadding(h)));
        const pill_h = h -| 4;
        const pill_y = y + 2;
        const radius = pill_h / 2;
        const fs = self.font.size;
        const ty: i32 = @intCast((pill_h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, pill_y))));
        for (0..n) |i| {
            const tag_idx = @as(u8, @intCast(i));
            const active = workspace.isTagActive(tag_idx);
            const urgent = workspace.isTagUrgent(tag_idx);
            const pill_w: u32 = 20;
            const bg = if (urgent) self.color_urgent else if (active) self.color_active else t.bar.item_background;
            const fg = if (urgent) self.color_urgent_text else if (active) self.color_active_text else self.color_inactive;
            if (bg.a > 0) {
                surface.fillRoundedRect(cx, pill_y, pill_w, pill_h, radius, bg);
            }
            const ch = if (i < self.symbols.len) self.symbols[i] else "?";
            self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, ch, cx + @as(i32, @intCast(pill_w / 2 -| 3)), ty, fg);
            cx += @as(i32, @intCast(pill_w + 4));
        }
    }
    pub fn count(self: *TagWidget) u8 { _ = self; return workspace.tag_state.tag_count; }
};

pub const ActiveWindow = struct {
    font: *text.Font,
    title: []const u8 = "",
    color: Color = t.colors.accent,
    pub fn init(font: *text.Font) ActiveWindow { return .{ .font = font, .title = "" }; }
    pub fn deinit(_: *ActiveWindow) void {}
    pub fn measure(self: *ActiveWindow, max_w: u32, h: u32) u32 {
        if (self.title.len == 0) return 0;
        const tw = self.font.measureText(self.title);
        const pad = edgePadding(h);
        return @min(tw + pad * 2, @min(max_w, 600));
    }
    pub fn render(self: *ActiveWindow, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        if (self.title.len == 0) return;
        drawWidgetBg(surface, x, y, w, h);
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        const max_text_w = w -| (pad * 2);
        if (max_text_w < 8) return;
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, self.title, x + @as(i32, @intCast(pad)), ty, self.color);
    }
};

pub const Clock = struct {
    font: *text.Font,
    color: Color = t.colors.accent,
    buf: [32]u8 = undefined,
    last_time: []const u8 = "",
    pub fn init(font: *text.Font) Clock { return .{ .font = font }; }
    pub fn deinit(_: *Clock) void {}
    pub fn measure(self: *Clock, _: u32, h: u32) u32 {
        const pad = edgePadding(h);
        return self.font.measureText(self.getTime()) + pad * 2;
    }
    pub fn render(self: *Clock, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        drawWidgetBg(surface, x, y, w, h);
        const pad = edgePadding(h);
        const time = self.getTime();
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, time, x + @as(i32, @intCast(pad)), ty, self.color);
    }
    fn getTime(self: *Clock) []const u8 {
        const now = unixTime();
        if (now <= 0) return "??:??";
        const tm = extern struct { sec: i32, min: i32, hour: i32, mday: i32, mon: i32, year: i32, wday: i32, yday: i32, isdst: i32 };
        const lr = struct { extern "c" fn localtime_r(timep: *const i64, result: *tm) ?*tm; };
        var result: tm = undefined;
        var now_copy = now;
        if (lr.localtime_r(&now_copy, &result) == null) return "??:??";
        self.last_time = std.fmt.bufPrint(&self.buf, "{d:0>2}:{d:0>2}", .{ @as(u8, @intCast(result.hour)), @as(u8, @intCast(result.min)) }) catch return "??:??";
        return self.last_time;
    }
};

pub const BatteryWidget = struct {
    font: *text.Font,
    color: Color = t.colors.accent,
    charging_color: Color = t.colors.accent,
    warning_color: Color = t.colors.warning,
    critical_color: Color = t.colors.critical,
    warning_level: u8 = 30,
    critical_level: u8 = 15,
    pub fn init(font: *text.Font) BatteryWidget { return .{ .font = font }; }
    pub fn deinit(_: *BatteryWidget) void {}
    pub fn measure(self: *BatteryWidget, _: u32, h: u32) u32 {
        const pad = edgePadding(h);
        return self.font.measureText("\u{f240} 100%") + pad * 2;
    }
    pub fn render(self: *BatteryWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        drawWidgetBg(surface, x, y, w, h);
        var buf: [16]u8 = undefined;
        const pct = if (battery.state.available) @as(u8, @intCast(@min(@as(u32, @intFromFloat(battery.state.percentage)), 100))) else 255;
        if (pct > 100) return;
        const color = if (battery.state.charging) self.charging_color else if (pct <= self.critical_level) self.critical_color else if (pct <= self.warning_level) self.warning_color else self.color;
        const icon = if (battery.state.charging) "\u{f0e7}" else if (pct >= 90) "\u{f240}" else if (pct >= 60) "\u{f241}" else if (pct >= 30) "\u{f242}" else "\u{f244}";
        const text_str = std.fmt.bufPrint(&buf, "{s} {d: >3}%", .{ icon, pct }) catch "BAT";
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, text_str, x + @as(i32, @intCast(pad)), ty, color);
    }
};

pub const VolumeWidget = struct {
    font: *text.Font,
    color: Color = t.colors.accent,
    muted_color: Color = t.colors.warning,
    pub fn init(font: *text.Font) VolumeWidget { return .{ .font = font }; }
    pub fn deinit(_: *VolumeWidget) void {}
    pub fn measure(self: *VolumeWidget, _: u32, h: u32) u32 {
        const pad = edgePadding(h);
        return self.font.measureText("\u{f028} 100%") + pad * 2;
    }
    pub fn render(self: *VolumeWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        drawWidgetBg(surface, x, y, w, h);
        var buf: [16]u8 = undefined;
        const pct = if (volume.state.available) @as(u8, @intCast(@min(@as(u32, @intFromFloat(volume.state.percentage)), 100))) else 0;
        const color = if (volume.state.muted) self.muted_color else self.color;
        const icon = if (volume.state.muted) "\u{f026}" else if (pct >= 60) "\u{f028}" else if (pct >= 20) "\u{f027}" else "\u{f6a9}";
        const text_str = std.fmt.bufPrint(&buf, "{s} {d: >3}%", .{ icon, pct }) catch "VOL";
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, text_str, x + @as(i32, @intCast(pad)), ty, color);
    }
};

pub const MprisWidget = struct {
    font: *text.Font,
    color: Color = t.colors.accent,
    playing_color: Color = t.colors.accent,
    paused_color: Color = t.colors.muted,
    pub fn init(font: *text.Font) MprisWidget { return .{ .font = font }; }
    pub fn deinit(_: *MprisWidget) void {}
    pub fn measure(self: *MprisWidget, _: u32, h: u32) u32 {
        if (!mpris.state.available or mpris.state.player_count == 0) return 0;
        const p = &mpris.state.players[mpris.state.active_idx];
        if (p.playback_status == .stopped or p.track_title.len == 0) return 0;
        const display = if (p.track_artist.len > 0)
            std.fmt.allocPrint(std.heap.page_allocator, "{s} - {s}", .{ p.track_artist, p.track_title }) catch return 0
        else
            p.track_title;
        defer if (p.track_artist.len > 0) std.heap.page_allocator.free(@constCast(display));
        const pad = edgePadding(h);
        return @min(self.font.measureText(display) + pad * 2, 400);
    }
    pub fn render(self: *MprisWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        if (!mpris.state.available or mpris.state.player_count == 0) return;
        const p = &mpris.state.players[mpris.state.active_idx];
        if (p.playback_status == .stopped or p.track_title.len == 0) return;
        if (w < 10) return;
        drawWidgetBg(surface, x, y, w, h);
        const icon = if (p.playback_status == .playing) "\u{f144}" else "\u{f28b}";
        const color = if (p.playback_status == .playing) self.playing_color else self.paused_color;
        const display = if (p.track_artist.len > 0)
            std.fmt.allocPrint(std.heap.page_allocator, "{s} {s} - {s}", .{ icon, p.track_artist, p.track_title }) catch return
        else
            std.fmt.allocPrint(std.heap.page_allocator, "{s} {s}", .{ icon, p.track_title }) catch return;
        defer std.heap.page_allocator.free(@constCast(display));
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, display, x + @as(i32, @intCast(pad)), ty, color);
    }
};

pub const NetworkWidget = struct {
    font: *text.Font,
    color: Color = t.colors.accent,
    offline_color: Color = t.colors.muted,
    pub fn init(font: *text.Font) NetworkWidget { return .{ .font = font }; }
    pub fn deinit(_: *NetworkWidget) void {}
    pub fn measure(self: *NetworkWidget, _: u32, h: u32) u32 {
        if (!network.state.available or network.state.device_count == 0) return 0;
        const pad = edgePadding(h);
        return self.font.measureText("\u{f1eb} WiFi") + pad * 2;
    }
    pub fn render(self: *NetworkWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        if (!network.state.available or network.state.device_count == 0) return;
        drawWidgetBg(surface, x, y, w, h);
        var buf: [32]u8 = undefined;
        var color = self.offline_color;
        var icon: []const u8 = "\u{faa8}";
        var label: []const u8 = "OFF";
        for (network.state.devices[0..network.state.device_count]) |*d| {
            if (d.state >= 70) {
                if (d.dev_type == .wifi) {
                    icon = if (d.strength >= 80) "\u{f1eb}" else if (d.strength >= 60) "\u{f1eb}" else if (d.strength >= 40) "\u{f1eb}" else "\u{f1eb}";
                    label = if (d.ssid.len > 0) d.ssid[0..@min(d.ssid.len, @as(usize, 8))] else "WiFi";
                    color = self.color;
                    break;
                } else if (d.dev_type == .ethernet) {
                    icon = "\u{f6ff}";
                    label = "ETH";
                    color = self.color;
                    break;
                }
            }
        }
        const text_str = std.fmt.bufPrint(&buf, "{s} {s}", .{ icon, label }) catch "NET";
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, text_str, x + @as(i32, @intCast(pad)), ty, color);
    }
};

pub const SysInfoWidget = struct {
    font: *text.Font,
    cpu_color: Color = t.colors.accent,
    cpu_warn_color: Color = t.colors.warning,
    cpu_crit_color: Color = t.colors.critical,
    mem_color: Color = t.colors.accent,
    temp_color: Color = t.colors.accent,
    temp_warn_color: Color = t.colors.warning,
    temp_crit_color: Color = t.colors.critical,
    warn_threshold: u8 = 70,
    crit_threshold: u8 = 90,
    pub fn init(font: *text.Font) SysInfoWidget { return .{ .font = font }; }
    pub fn deinit(_: *SysInfoWidget) void {}
    pub fn measure(self: *SysInfoWidget, _: u32, h: u32) u32 {
        const pad = edgePadding(h);
        return self.font.measureText("\u{f2db} 100% \u{f538} 100% \u{f2c7} 99\xb0") + pad * 2;
    }
    pub fn render(self: *SysInfoWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        drawWidgetBg(surface, x, y, w, h);
        var buf: [64]u8 = undefined;
        const cpu_color = if (sysinfo.state.cpu_percent >= self.crit_threshold) self.cpu_crit_color else if (sysinfo.state.cpu_percent >= self.warn_threshold) self.cpu_warn_color else self.cpu_color;
        const temp_c = @as(u8, @intFromFloat(sysinfo.state.temp_celsius));
        const text_str = std.fmt.bufPrint(&buf, "\u{f2db} {d: >3}% \u{f538} {d: >3}% \u{f2c7} {d: >2}\xb0", .{ sysinfo.state.cpu_percent, sysinfo.state.mem_percent, temp_c }) catch "SYS";
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, text_str, x + @as(i32, @intCast(pad)), ty, cpu_color);
    }
};

pub const BrightnessWidget = struct {
    font: *text.Font,
    color: Color = t.colors.accent,
    pub fn init(font: *text.Font) BrightnessWidget { return .{ .font = font }; }
    pub fn deinit(_: *BrightnessWidget) void {}
    pub fn measure(self: *BrightnessWidget, _: u32, h: u32) u32 {
        if (!brightness.state.available) return 0;
        const pad = edgePadding(h);
        return self.font.measureText("\u{f185} 100%") + pad * 2;
    }
    pub fn render(self: *BrightnessWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        if (!brightness.state.available) return;
        drawWidgetBg(surface, x, y, w, h);
        var buf: [16]u8 = undefined;
        const pct = if (brightness.state.count > 0 and brightness.state.backlights[0].max_brightness > 0)
            brightness.state.backlights[0].brightness * 100 / brightness.state.backlights[0].max_brightness
        else 0;
        const text_str = std.fmt.bufPrint(&buf, "\u{f185} {d: >3}%", .{pct}) catch "BRT";
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, text_str, x + @as(i32, @intCast(pad)), ty, self.color);
    }
};

pub const PowerProfilesWidget = struct {
    font: *text.Font,
    color: Color = t.colors.accent,
    pub fn init(font: *text.Font) PowerProfilesWidget { return .{ .font = font }; }
    pub fn deinit(_: *PowerProfilesWidget) void {}
    pub fn measure(self: *PowerProfilesWidget, _: u32, h: u32) u32 {
        if (!power_profiles.state.available) return 0;
        const pad = edgePadding(h);
        return self.font.measureText("\u{f085}") + pad * 2;
    }
    pub fn render(self: *PowerProfilesWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        if (!power_profiles.state.available) return;
        drawWidgetBg(surface, x, y, w, h);
        const icon = "\u{f085}";
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, icon, x + @as(i32, @intCast(pad)), ty, self.color);
    }
};

pub const SystemTrayWidget = struct {
    font: *text.Font,
    pub fn init(font: *text.Font) SystemTrayWidget { return .{ .font = font }; }
    pub fn deinit(_: *SystemTrayWidget) void {}
    pub fn measure(_: *SystemTrayWidget, _: u32, h: u32) u32 {
        if (!system_tray.state.available or system_tray.state.item_count == 0) return 0;
        const pad = edgePadding(h);
        return @as(u32, @intCast(system_tray.state.item_count)) * 20 + pad * 2;
    }
    pub fn render(_: *SystemTrayWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        _ = w;
        if (!system_tray.state.available or system_tray.state.item_count == 0) return;
        const pad = edgePadding(h);
        var cx = x + @as(i32, @intCast(pad));
        for (0..system_tray.state.item_count) |_| {
            surface.fillRect(cx, y + @as(i32, @intCast(h / 4)), @as(u32, @intCast(h / 2)), @as(u32, @intCast(h / 2)), .{ .r = 0x6c, .g = 0x70, .b = 0x86, .a = 0xff });
            cx += 20;
        }
    }
};

pub const ButtonWidget = struct {
    font: *text.Font,
    icon: []const u8,
    command: []const u8,
    color: Color = t.colors.accent,
    pub fn init(font: *text.Font, icon: []const u8, command: []const u8) ButtonWidget {
        return .{ .font = font, .icon = icon, .command = command };
    }
    pub fn deinit(_: *ButtonWidget) void {}
    pub fn measure(self: *ButtonWidget, _: u32, h: u32) u32 {
        const pad = edgePadding(h);
        return self.font.measureText(self.icon) + pad * 2;
    }
    pub fn render(self: *ButtonWidget, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        drawWidgetBg(surface, x, y, w, h);
        const pad = edgePadding(h);
        const fs = self.font.size;
        const ty: i32 = @intCast((h -| @as(u32, @intFromFloat(fs))) / 2 + @as(u32, @intFromFloat(fs)) - 2 + @as(u32, @intCast(@max(0, y))));
        self.font.drawText(surface.pixels, surface.stride_pixels, surface.width, surface.height, self.icon, x + @as(i32, @intCast(pad)), ty, self.color);
    }
};

fn unixTime() i64 {
    const ts = extern struct { sec: i64, nsec: i64 };
    const c = struct { extern "c" fn clock_gettime(clock_id: c_int, tp: *ts) c_int; };
    var clock_ts: ts = undefined;
    return if (c.clock_gettime(0, &clock_ts) == 0) clock_ts.sec else 0;
}

pub const WidgetEnum = union(enum) {
    spacer: Spacer,
    separator: Separator,
    tags: TagWidget,
    active_window: ActiveWindow,
    clock: Clock,
    battery: BatteryWidget,
    volume: VolumeWidget,
    mpris: MprisWidget,
    network: NetworkWidget,
    sysinfo: SysInfoWidget,
    brightness: BrightnessWidget,
    power_profiles: PowerProfilesWidget,
    system_tray: SystemTrayWidget,
    button_menu: ButtonWidget,
    button_power: ButtonWidget,

    pub fn measure(self: *WidgetEnum, max_w: u32, bar_h: u32) u32 {
        return switch (self.*) {
            inline else => |*widget| widget.measure(max_w, bar_h),
        };
    }
    pub fn render(self: *WidgetEnum, surface: *rdr.Surface, x: i32, y: i32, w: u32, h: u32) void {
        switch (self.*) {
            inline else => |*widget| widget.render(surface, x, y, w, h),
        }
    }
    pub fn deinit(self: *WidgetEnum) void {
        switch (self.*) {
            inline else => |*widget| widget.deinit(),
        }
    }
};
