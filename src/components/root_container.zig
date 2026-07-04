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
const seat = @import("../seat.zig");
const volume = @import("../service/volume.zig");
const workspace = @import("../workspace.zig");
const theme = @import("../theme.zig");

const log = std.log.scoped(.RootContainer);

const max_widgets = Config.max_widgets_per_section;
const HitEntry = struct {
    section: enum { left, center, right },
    index: usize,
    rect: Rect,
};

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

hit_areas: [max_widgets * 3]HitEntry = undefined,
hit_count: usize = 0,

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
    const layout = &Config.global_layout;
    self.createSection(&self.left_widgets, &self.left_count, layout.left, "left");
    self.createSection(&self.center_widgets, &self.center_count, layout.center, "center");
    self.createSection(&self.right_widgets, &self.right_count, layout.right, "right");
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
    if (std.mem.eql(u8, name, "battery")) return widgets.WidgetEnum{ .battery = widgets.BatteryWidget.init(font) };
    if (std.mem.eql(u8, name, "volume")) return widgets.WidgetEnum{ .volume = widgets.VolumeWidget.init(font) };
    if (std.mem.eql(u8, name, "mpris")) return widgets.WidgetEnum{ .mpris = widgets.MprisWidget.init(font) };
    if (std.mem.eql(u8, name, "network")) return widgets.WidgetEnum{ .network = widgets.NetworkWidget.init(font) };
    if (std.mem.eql(u8, name, "sysinfo")) return widgets.WidgetEnum{ .sysinfo = widgets.SysInfoWidget.init(font) };
    if (std.mem.eql(u8, name, "brightness")) return widgets.WidgetEnum{ .brightness = widgets.BrightnessWidget.init(font) };
    if (std.mem.eql(u8, name, "power_profiles")) return widgets.WidgetEnum{ .power_profiles = widgets.PowerProfilesWidget.init(font) };
    if (std.mem.eql(u8, name, "system_tray")) return widgets.WidgetEnum{ .system_tray = widgets.SystemTrayWidget.init(font) };
    if (std.mem.eql(u8, name, "spacer")) return widgets.WidgetEnum{ .spacer = widgets.Spacer.init() };
    if (std.mem.eql(u8, name, "separator")) return widgets.WidgetEnum{ .separator = widgets.Separator.init() };
    if (std.mem.eql(u8, name, "button_menu")) return widgets.WidgetEnum{ .button_menu = widgets.ButtonWidget.init(font, "\u{ef0a}", "otter-launcher") };
    if (std.mem.eql(u8, name, "button_power")) return widgets.WidgetEnum{ .button_power = widgets.ButtonWidget.init(font, "\u{23fb}", "wlogout") };
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

fn syncState(self: *RootContainer) void {
    inline for ([_][]widgets.WidgetEnum{ &self.left_widgets, &self.center_widgets, &self.right_widgets }) |section| {
        for (section) |*w| {
            if (w.* == .active_window) {
                w.active_window.title = self.wayland_context.getFocusedTitle();
            }
        }
    }
}

fn verticalInset(height: Size) Size {
    return @min(4, @max(1, height / 8));
}

fn edgePadding(h: u32) u32 {
    return @max(3, h / 8);
}

fn buildHitAreas(self: *RootContainer, clip: Rect) void {
    const layout_padding: u32 = Config.getLayoutPadding();
    const inset = verticalInset(clip.height);
    const widget_height = clip.height -| (inset * 2);
    const inner_width = clip.width -| (layout_padding * 2);
    const section_width = inner_width / 3;
    self.hit_count = 0;

    const left_col = Rect{
        .x = @intCast(layout_padding),
        .y = 0,
        .width = section_width,
        .height = clip.height,
    };
    const center_col = Rect{
        .x = @intCast(layout_padding + section_width),
        .y = 0,
        .width = section_width,
        .height = clip.height,
    };
    const right_col = Rect{
        .x = @intCast(layout_padding + (section_width * 2)),
        .y = 0,
        .width = inner_width -| (section_width * 2),
        .height = clip.height,
    };

    self.layoutSectionLeft(&self.left_widgets, self.left_count, left_col, widget_height, layout_padding, inset);
    self.layoutSectionCenter(&self.center_widgets, self.center_count, center_col, widget_height, layout_padding, inset);
    self.layoutSectionRight(&self.right_widgets, self.right_count, right_col, widget_height, layout_padding, inset);
}

fn layoutSectionLeft(self: *RootContainer, section: *[max_widgets]widgets.WidgetEnum, count: usize, col: Rect, widget_height: u32, layout_padding: u32, inset: u32) void {
    var x: i32 = col.x;
    const max_x: i32 = col.x + @as(i32, @intCast(col.width));
    for (section[0..count], 0..) |*w, i| {
        const initial_width = w.measure(0, widget_height);
        if (initial_width == 0) continue;
        if (x + @as(i32, @intCast(initial_width)) > max_x) break;
        self.hit_areas[self.hit_count] = .{
            .section = .left, .index = i,
            .rect = .{ .x = x, .y = @intCast(inset), .width = initial_width, .height = widget_height },
        };
        self.hit_count += 1;
        x += @as(i32, @intCast(initial_width + layout_padding));
    }
}

fn layoutSectionCenter(self: *RootContainer, section: *[max_widgets]widgets.WidgetEnum, count: usize, col: Rect, widget_height: u32, layout_padding: u32, inset: u32) void {
    if (count == 0) return;
    var widths: [max_widgets]u32 = .{0} ** max_widgets;
    var total_width: u32 = 0;
    var widget_count: usize = 0;
    for (section[0..count], 0..) |*w, i| {
        const w_w = w.measure(0, widget_height);
        if (w_w == 0) continue;
        widths[i] = w_w;
        total_width += w_w;
        widget_count += 1;
    }
    if (widget_count == 0) return;
    if (widget_count > 1) total_width += @as(u32, @intCast(widget_count - 1)) * layout_padding;
    total_width = @min(total_width, col.width);
    var group_x: i32 = col.x + @as(i32, @intCast((col.width -| total_width) / 2));
    const col_end: i32 = col.x + @as(i32, @intCast(col.width));
    for (section[0..count], 0..) |*w, i| {
        const w_w = widths[i];
        if (w_w == 0) continue;
        _ = w;
        self.hit_areas[self.hit_count] = .{
            .section = .center, .index = i,
            .rect = .{ .x = group_x, .y = @as(i32, @intCast(inset)), .width = w_w, .height = widget_height },
        };
        self.hit_count += 1;
        group_x += @as(i32, @intCast(widths[i] + layout_padding));
        if (group_x > col_end) break;
    }
}

fn layoutSectionRight(self: *RootContainer, section: *[max_widgets]widgets.WidgetEnum, count: usize, col: Rect, widget_height: u32, layout_padding: u32, inset: u32) void {
    var right_edge: i32 = col.x + @as(i32, @intCast(col.width));
    const min_x: i32 = col.x;
    var i: usize = count;
    while (i > 0) {
        i -= 1;
        const w = &section[i];
        const initial_width = w.measure(0, widget_height);
        if (initial_width == 0) continue;
        const widget_x = right_edge - @as(i32, @intCast(initial_width));
        if (widget_x < min_x) break;
        self.hit_areas[self.hit_count] = .{
            .section = .right, .index = i,
            .rect = .{ .x = widget_x, .y = @intCast(inset), .width = initial_width, .height = widget_height },
        };
        self.hit_count += 1;
        right_edge = widget_x - @as(i32, @intCast(layout_padding));
    }
}

fn widgetPtr(self: *RootContainer, entry: HitEntry) *widgets.WidgetEnum {
    return switch (entry.section) {
        .left => &self.left_widgets[entry.index],
        .center => &self.center_widgets[entry.index],
        .right => &self.right_widgets[entry.index],
    };
}

fn findWidgetAtPoint(self: *RootContainer, point: Point) ?HitEntry {
    for (self.hit_areas[0..self.hit_count]) |entry| {
        if (entry.rect.containsPoint(point)) return entry;
    }
    return null;
}

pub fn drawFrame(self: *RootContainer, surface: *rdr.Surface, clip: Rect) void {
    self.syncState();
    self.buildHitAreas(clip);

    const t = &theme.default;
    const bar_bg = t.panelColor(t.bar.background);

    if (bar_bg.a > 0) {
        surface.fillRect(0, 0, clip.width, clip.height, bar_bg);
    } else {
        surface.fillRect(0, 0, clip.width, clip.height, Color.transparent);
    }

    if (t.bar.border.a > 0) {
        surface.fillRect(0, @as(i32, @intCast(clip.height)) - 1, clip.width, 1, t.bar.border);
    }

    if (t.bar.group_background.a > 0 or t.bar.group_border.a > 0) {
        const layout_padding: u32 = Config.getLayoutPadding();
        const inner_width = clip.width -| (layout_padding * 2);
        const section_width = inner_width / 3;
        const group_bg = t.panelColor(t.bar.group_background);
        const radius = t.density.panel_radius;

        for ([_]i32{
            @as(i32, @intCast(layout_padding)),
            @as(i32, @intCast(layout_padding + section_width)),
            @as(i32, @intCast(layout_padding + (section_width * 2))),
        }, 0..) |sx, si| {
            var gw: i32 = @intCast(section_width);
            if (si == 2) gw = @intCast(inner_width -| (section_width * 2));
            if (gw > 0) {
                if (group_bg.a > 0) {
                    if (radius > 0) {
                        surface.fillRoundedRect(sx, 0, @intCast(gw), clip.height, radius, group_bg);
                    } else {
                        surface.fillRect(sx, 0, @intCast(gw), clip.height, group_bg);
                    }
                }
                if (t.bar.group_border.a > 0) {
                    surface.fillRect(sx, 0, @intCast(gw), 1, t.bar.group_border);
                    surface.fillRect(sx, @as(i32, @intCast(clip.height)) - 1, @intCast(gw), 1, t.bar.group_border);
                }
            }
        }
    }

    for (self.hit_areas[0..self.hit_count]) |entry| {
        if (entry.section != .left) continue;
        const w = self.widgetPtr(entry);
        w.render(surface, entry.rect.x, entry.rect.y, entry.rect.width, entry.rect.height);
    }
    for (self.hit_areas[0..self.hit_count]) |entry| {
        if (entry.section != .center) continue;
        const w = self.widgetPtr(entry);
        w.render(surface, entry.rect.x, entry.rect.y, entry.rect.width, entry.rect.height);
    }
    for (self.hit_areas[0..self.hit_count]) |entry| {
        if (entry.section != .right) continue;
        const w = self.widgetPtr(entry);
        w.render(surface, entry.rect.x, entry.rect.y, entry.rect.width, entry.rect.height);
    }
}

pub fn motion(self: *RootContainer, point: Point) void {
    self.last_motion = point;
    _ = self.findWidgetAtPoint(point);
}

pub fn leave(self: *RootContainer) void {
    self.last_motion = null;
}

pub fn click(self: *RootContainer, btn: anytype) void {
    const point = self.last_motion orelse return;
    const entry = self.findWidgetAtPoint(point) orelse return;
    const w = self.widgetPtr(entry);
    switch (w.*) {
        .tags => {
            const tag_count = workspace.tag_state.tag_count;
            const pill_w: u32 = 20;
            const pill_gap: u32 = 4;
            const pad = edgePadding(@intCast(entry.rect.height));
            const start_x = entry.rect.x + @as(i32, @intCast(pad));
            const rel_x = point.x - start_x;
            if (rel_x >= 0) {
                const tag_idx = @as(usize, @intCast(rel_x)) / (pill_w + pill_gap);
                if (tag_idx < tag_count) {
                    log.info("Tag {} clicked", .{tag_idx + 1});
                    workspace.switchToTag(@intCast(tag_idx));
                }
            }
        },
        .volume => {
            if (btn == .left) {
                volume.toggleMute();
                if (self.output) |o| {
                    o.full_redraw = true;
                    o.requestFrame();
                }
            }
        },
        .button_menu, .button_power => {
            const cmd = if (w.* == .button_menu) w.button_menu.command else w.button_power.command;
            runCommand(cmd);
        },
        else => {},
    }
}

fn runCommand(cmd: []const u8) void {
    if (cmd.len == 0) return;
    var cmd_buf: [512]u8 = undefined;
    if (cmd.len >= cmd_buf.len) return;
    @memcpy(cmd_buf[0..cmd.len], cmd);
    cmd_buf[cmd.len] = 0;
    const c = struct {
        extern "c" fn fork() c_int;
        extern "c" fn setsid() c_int;
        extern "c" fn system(cmd: [*:0]const u8) c_int;
        extern "c" fn _exit(status: c_int) noreturn;
    };
    const pid = c.fork();
    if (pid == 0) {
        _ = c.setsid();
        _ = c.system(cmd_buf[0..cmd.len :0]);
        c._exit(0);
    }
}

pub fn scroll(self: *RootContainer, _: anytype, value: i32) void {
    const point = self.last_motion orelse return;
    const entry = self.findWidgetAtPoint(point) orelse return;
    const w = self.widgetPtr(entry);
    switch (w.*) {
        .volume => {
            const delta: i8 = if (value > 0) -5 else 5;
            volume.setVolume(delta);
            if (self.output) |o| {
                o.full_redraw = true;
                o.requestFrame();
            }
        },
        else => {},
    }
}

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
