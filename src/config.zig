const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const config_parser = @import("config_parser.zig");
const ConfigFile = config_parser.ConfigFile;
const WidgetList = config_parser.WidgetList;
const theme_mod = @import("theme.zig");

const c = std.c;
const log = std.log.scoped(.Config);

pub const Theme = theme_mod.Theme;

pub const min_height = 15;
pub const default_height = 38;
pub const default_font_path: [:0]const u8 = "/run/current-system/sw/share/X11/fonts/JetBrainsMonoNerdFont-Regular.ttf";
pub const max_widgets_per_section = 16;

pub const Position = enum { top, bottom };

pub const General = struct {
    height: u16 = default_height,
    padding: u16 = 8,
    position: Position = .top,
    font_path: ?[]const u8 = null,
    background_color: ?u32 = null,
    foreground_color: ?u32 = null,
};

pub const WidgetNames = struct {
    left: []const []const u8 = &.{},
    center: []const []const u8 = &.{},
    right: []const []const u8 = &.{},
};

pub const Config = @This();

pub var global: Config = .{};
pub var global_theme: Theme = .{};
pub var global_layout: WidgetNames = .{};

var global_allocator: ?mem.Allocator = null;
var global_watcher: ?config_parser.Watcher = null;
var global_theme_watcher: ?config_parser.Watcher = null;
var global_config_path: ?[]const u8 = null;
var global_theme_path: ?[]const u8 = null;

general: General = .{},

pub fn getHeight() u16 {
    return global.general.height;
}

pub fn getPadding() u16 {
    return global.general.padding;
}

pub fn getLayoutPadding() u16 {
    return global_theme.bar.layout_padding;
}

pub fn isBottom() bool {
    return global.general.position == .bottom;
}

pub fn getBackgroundColor() u32 {
    const bg = global.general.background_color orelse {
        const t = global_theme.bar.background;
        return @as(u32, @intCast(t.r)) << 24 | @as(u32, @intCast(t.g)) << 16 | @as(u32, @intCast(t.b)) << 8 | @as(u32, @intCast(t.a));
    };
    return bg;
}

pub fn initGlobal(allocator: mem.Allocator) void {
    global_allocator = allocator;

    const path = config_parser.findConfigPath(allocator, "mist-bar.conf") orelse {
        log.info("No config file found, using defaults", .{});
        const home_raw = c.getenv("HOME") orelse return;
        const home = std.mem.span(home_raw);
        var buf: [512]u8 = undefined;
        const user_path = std.fmt.bufPrint(&buf, "{s}/.config/mist-shell/mist-bar.conf", .{home}) catch return;
        const duped = allocator.dupe(u8, user_path) catch return;
        config_parser.writeDefaultConfig(duped) catch {
            log.warn("Failed to write default config", .{});
        };
        global_layout = WidgetNames{
            .left = &.{ "button_menu", "tags", "active_window", "mpris" },
            .center = &.{"clock"},
            .right = &.{ "system_tray", "sysinfo", "network", "volume", "brightness", "battery", "power_profiles" },
        };
        return;
    };
    defer allocator.free(path);

    var cf = config_parser.parseConfigFile(allocator, path) catch |err| {
        log.warn("Failed to parse config at {s}: {s}", .{ path, @errorName(err) });
        global_layout = WidgetNames{
            .left = &.{ "tags", "active_window", "mpris" },
            .center = &.{"clock"},
            .right = &.{ "system_tray", "sysinfo", "network", "volume", "brightness", "battery", "power_profiles" },
        };
        return;
    };

    global.general.height = @max(cf.getInt("height", default_height), min_height);
    global.general.padding = cf.getInt("padding", 8);
    global.general.position = if (std.mem.eql(u8, cf.getString("position", "top"), "bottom")) .bottom else .top;

    const bg_raw = cf.getColor("background_color", 0);
    if (bg_raw != 0) global.general.background_color = bg_raw;
    const fg_raw = cf.getColor("foreground_color", 0);
    if (fg_raw != 0) global.general.foreground_color = fg_raw;

    const font = cf.getString("font_path", "");
    global.general.font_path = if (font.len > 0) allocator.dupe(u8, font) catch null else null;

    if (cf.get("layout_left")) |_| {
        var left_list = cf.getWidgetList("layout_left");
        var center_list = cf.getWidgetList("layout_center");
        var right_list = cf.getWidgetList("layout_right");
        global_layout = .{
            .left = allocator.dupe([]const u8, left_list.slice()) catch &.{},
            .center = allocator.dupe([]const u8, center_list.slice()) catch &.{},
            .right = allocator.dupe([]const u8, right_list.slice()) catch &.{},
        };
    } else {
        global_layout = WidgetNames{
            .left = &.{ "button_menu", "tags", "active_window", "mpris" },
            .center = &.{"clock"},
            .right = &.{ "system_tray", "sysinfo", "network", "volume", "brightness", "battery", "power_profiles" },
        };
    }

    global_config_path = allocator.dupe(u8, path) catch null;
    cf.deinit();
    log.info("Config loaded from {s}", .{path});
}

pub fn initWatcher() !void {
    const allocator = global_allocator orelse return error.NotReady;
    const path = global_config_path orelse return error.NotReady;
    global_watcher = try config_parser.Watcher.init(allocator, path);
}

pub fn getWatcherFd() ?posix.fd_t {
    if (global_watcher) |*w| return w.getFd();
    return null;
}

pub fn checkWatcherEvents() bool {
    const w = &(global_watcher orelse return false);
    return w.hasEvent();
}

pub const ReloadResult = struct {
    success: bool = false,
    layout_changed: bool = false,
    font_changed: bool = false,
    colors_changed: bool = false,
};

pub fn reloadGlobal() ReloadResult {
    const allocator = global_allocator orelse return .{};
    const path = global_config_path orelse return .{};
    const old_path = allocator.dupe(u8, path) catch return .{};
    defer allocator.free(old_path);

    const old_height = global.general.height;

    var cf = config_parser.parseConfigFile(allocator, path) catch return .{};
    defer cf.deinit();

    var result = ReloadResult{ .success = true };

    global.general.height = @max(cf.getInt("height", default_height), min_height);
    global.general.padding = cf.getInt("padding", 8);
    global.general.position = if (std.mem.eql(u8, cf.getString("position", "top"), "bottom")) .bottom else .top;

    if (global.general.height != old_height) result.colors_changed = true;

    if (cf.get("layout_left") != null) {
        var left_list = cf.getWidgetList("layout_left");
        var center_list = cf.getWidgetList("layout_center");
        var right_list = cf.getWidgetList("layout_right");
        global_layout = .{
            .left = allocator.dupe([]const u8, left_list.slice()) catch global_layout.left,
            .center = allocator.dupe([]const u8, center_list.slice()) catch global_layout.center,
            .right = allocator.dupe([]const u8, right_list.slice()) catch global_layout.right,
        };
        result.layout_changed = true;
    }

    log.info("Config reloaded from {s}", .{path});
    return result;
}

pub fn deinitGlobal() void {
    if (global_watcher) |*w| {
        if (global_allocator) |a| w.deinit(a);
    }
    if (global_theme_watcher) |*w| {
        if (global_allocator) |a| w.deinit(a);
    }
    if (global_allocator) |allocator| {
        if (global_config_path) |p| allocator.free(p);
        if (global_theme_path) |p| allocator.free(p);
        if (global.general.font_path) |p| allocator.free(p);
    }
    global = .{};
    global_theme = .{};
    global_layout = .{};
    global_allocator = null;
    global_config_path = null;
    global_theme_path = null;
    global_watcher = null;
    global_theme_watcher = null;
}
