const std = @import("std");
const geo = @import("../geo.zig");
const rdr = @import("../shell/render.zig");
const text = @import("../shell/render/text.zig");
const Wayland = @import("../wayland.zig");
const wl = Wayland.wl;

const Point = geo.Point;
const Rect = geo.Rect;
const Size = geo.Size;
const Color = rdr.Color;

const Output = @import("../output.zig").Output;
const widgets = @import("../widget/registry.zig");
const Config = @import("../config.zig");

const log = std.log.scoped(.RootContainer);

const max_widgets = 16;

pub const RootContainer = @This();

area: Rect = .zero,
last_motion: ?Point = null,
full_redraw: bool = true,
allocator: std.mem.Allocator = std.heap.page_allocator,

wayland_context: *Wayland,
output: ?*Output = null,

font: ?*text.Font = null,

left_widgets: [max_widgets]widgets.WidgetEnum = undefined,
left_count: usize = 0,
center_widgets: [max_widgets]widgets.WidgetEnum = undefined,
center_count: usize = 0,
right_widgets: [max_widgets]widgets.WidgetEnum = undefined,
right_count: usize = 0,

pub fn init(
    allocator: std.mem.Allocator,
    area: Rect,
    _: *wl.Output,
    output_name: []const u8,
    wayland_context: *Wayland,
    font_path: [:0]const u8,
) RootContainer {
    _ = output_name;

    var rc = RootContainer{
        .area = area,
        .allocator = allocator,
        .wayland_context = wayland_context,
    };

    rc.loadFont(font_path) catch {};
    rc.createWidgets();
    return rc;
}

fn loadFont(self: *RootContainer, font_path: [:0]const u8) !void {
    const ptr = try self.allocator.create(text.Font);
    errdefer self.allocator.destroy(ptr);
    ptr.* = try text.Font.init(font_path, 14);
    self.font = ptr;
}

fn createWidgets(self: *RootContainer) void {
    self.createSection(&self.left_widgets, &self.left_count, &Config.default_layout.left, "left");
    self.createSection(&self.center_widgets, &self.center_count, &Config.default_layout.center, "center");
    self.createSection(&self.right_widgets, &self.right_count, &Config.default_layout.right, "right");
}

fn createSection(self: *RootContainer, widgets_buf: *[max_widgets]widgets.WidgetEnum, count: *usize, names: []const []const u8, tag: []const u8) void {
    const font = self.font orelse return;
    for (names) |name| {
        if (count.* >= max_widgets) {
            log.warn("Too many widgets in section '{s}'", .{tag});
            break;
        }
        widgets_buf[count.*] = createWidgetByName(name, font) catch continue;
        count.* += 1;
    }
}

fn createWidgetByName(name: []const u8, font: *text.Font) !widgets.WidgetEnum {
    if (std.mem.eql(u8, name, "tags")) return widgets.WidgetEnum{ .tags = widgets.TagWidget.init(font) };
    if (std.mem.eql(u8, name, "active_window")) return widgets.WidgetEnum{ .active_window = widgets.ActiveWindow.init(font) };
    if (std.mem.eql(u8, name, "clock")) return widgets.WidgetEnum{ .clock = widgets.Clock.init(font) };
    if (std.mem.eql(u8, name, "battery")) return widgets.WidgetEnum{ .battery = widgets.BatteryStub.init(font) };
    if (std.mem.eql(u8, name, "volume")) return widgets.WidgetEnum{ .volume = widgets.VolumeStub.init(font) };
    if (std.mem.eql(u8, name, "spacer")) return widgets.WidgetEnum{ .spacer = widgets.Spacer.init() };
    if (std.mem.eql(u8, name, "separator")) return widgets.WidgetEnum{ .separator = widgets.Separator.init() };
    log.warn("Unknown widget type: '{s}'", .{name});
    return error.UnknownWidget;
}

pub fn subscribeWidgets(_: *RootContainer) void {}

pub fn setOutput(self: *RootContainer, output: *Output) void {
    self.output = output;
}

pub fn setArea(self: *RootContainer, area: Rect) void {
    self.area = area;
    self.full_redraw = true;
}

pub fn deinit(self: *RootContainer) void {
    for (self.left_widgets[0..self.left_count]) |*w| w.deinit();
    for (self.center_widgets[0..self.center_count]) |*w| w.deinit();
    for (self.right_widgets[0..self.right_count]) |*w| w.deinit();
    if (self.font) |f| {
        f.deinit();
        self.allocator.destroy(f);
    }
}

pub fn needsRedraw(self: *RootContainer) bool {
    return self.full_redraw;
}

pub fn collectDamage(_: *RootContainer, _: *rdr.DamageTracker) void {}

pub fn syncState(self: *RootContainer) void {
    for (self.left_widgets[0..self.left_count]) |*w| {
        if (w.* == .active_window) {
            w.active_window.title = self.wayland_context.getFocusedTitle();
        }
    }
    for (self.right_widgets[0..self.right_count]) |*w| {
        if (w.* == .active_window) {
            w.active_window.title = self.wayland_context.getFocusedTitle();
        }
    }
}

pub fn drawFrame(self: *RootContainer, surface: *rdr.Surface, clip: Rect) void {
    self.syncState();
    const padding: i32 = 8;
    const spacing: i32 = 4;
    const width: i32 = @intCast(clip.width);
    const height: u32 = @intCast(clip.height);

    // Left section: pack from left edge
    var left_end: i32 = padding;
    for (self.left_widgets[0..self.left_count]) |*w| {
        const w_w = w.measure(@intCast(@max(0, width - left_end)), height);
        w.render(surface, left_end, 0, w_w, height);
        left_end += @intCast(w_w + spacing);
    }

    // Right section: pack from right edge
    const right_start: i32 = width - padding;
    var right_positions: [max_widgets]i32 = undefined;
    var right_widths: [max_widgets]u32 = undefined;
    {
        var i: usize = 0;
        var rp = right_start;
        while (i < self.right_count) : (i += 1) {
            const w = &self.right_widgets[i];
            const w_w = w.measure(@intCast(@max(0, rp - padding)), height);
            rp -= @intCast(w_w);
            right_positions[i] = rp;
            right_widths[i] = w_w;
            rp -= spacing;
        }
    }
    for (0..self.right_count) |i| {
        const idx = self.right_count - 1 - i;
        self.right_widgets[idx].render(surface, right_positions[idx], 0, right_widths[idx], height);
    }

    // Center section: center between left_end and right_start
    const center_available = right_start - left_end;
    if (center_available > 0 and self.center_count > 0) {
        var total_center_width: u32 = 0;
        var center_widths: [max_widgets]u32 = undefined;
        for (self.center_widgets[0..self.center_count], 0..) |*w, i| {
            const w_w = w.measure(@intCast(@max(0, center_available - @as(i32, @intCast(total_center_width)))), height);
            center_widths[i] = w_w;
            total_center_width += w_w;
            if (i + 1 < self.center_count) total_center_width += spacing;
        }
        var center_x = left_end + @divTrunc(center_available - @as(i32, @intCast(total_center_width)), 2);
        for (self.center_widgets[0..self.center_count], 0..) |*w, i| {
            w.render(surface, center_x, 0, center_widths[i], height);
            center_x += @intCast(center_widths[i] + spacing);
        }
    }
}

pub fn getWidgetByName(_: *RootContainer, _: []const u8) ?*Widget {
    return null;
}

pub fn getWidgetWidth(_: *RootContainer, _: []const u8) Size {
    return 0;
}

pub fn setWidgetArea(_: *RootContainer, _: []const u8, _: Rect) void {}

pub fn markAllWidgetsFullRedraw(_: *RootContainer) void {}

pub fn motion(_: *RootContainer, _: Point) void {}

pub fn leave(_: *RootContainer) void {}

pub fn click(_: *RootContainer, _: anytype) void {}

pub fn scroll(_: *RootContainer, _: anytype, _: i32) void {}

pub fn getCursorShape(_: *RootContainer) Wayland.CursorShape {
    return .default;
}

pub fn handlePopupMotion(_: *RootContainer, _: Point) void {}
pub fn handlePopupClick(_: *RootContainer, _: Point, _: anytype) void {}
pub fn handlePopupRelease(_: *RootContainer, _: Point, _: anytype) void {}
pub fn getPopupCursorShape(_: *RootContainer, _: Point) Wayland.CursorShape {
    return .default;
}
pub fn handlePopupScroll(_: *RootContainer, _: Point, _: anytype, _: i32) void {}

pub const Widget = struct {};
