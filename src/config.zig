const std = @import("std");
const mem = std.mem;

const log = std.log.scoped(.Config);

pub const Config = @This();

pub const Position = enum { top, bottom };

pub const min_height = 15;
pub const default_height = 38;
pub const default_font_path: [:0]const u8 = "/run/current-system/sw/share/X11/fonts/DejaVuSans.ttf";
pub const max_widgets_per_section = 16;

pub const default_layout = struct {
    pub const left = [_][]const u8{"tags"};
    pub const center = [_][]const u8{};
    pub const right = [_][]const u8{"active_window", "clock", "battery", "volume"};
};

pub var global: Config = .{};
pub var global_allocator: ?std.mem.Allocator = null;

general: General = .{},

pub const General = struct {
    height: ?u16 = null,
    padding: ?u16 = null,
    position: Position = .top,
    font_path: ?[]const u8 = null,
    background_color: ?u32 = null,
    foreground_color: ?u32 = null,
    width: ?u16 = null,
};

pub fn getHeight() u16 {
    return global.general.height orelse default_height;
}

pub fn getPadding() u16 {
    return global.general.padding orelse 8;
}

pub fn isBottom() bool {
    return global.general.position == .bottom;
}

pub fn initGlobal(allocator: std.mem.Allocator) void {
    global_allocator = allocator;
    global = .{};
    log.info("Config initialized with defaults", .{});
}

pub fn deinitGlobal() void {
    global = .{};
    global_allocator = null;
}

pub fn validate(_: *Config) void {}

pub fn getWatcherFd() ?std.posix.fd_t {
    return null;
}

pub fn checkWatcherEvents() bool {
    return false;
}

pub const ReloadResult = struct {
    success: bool = false,
    layout_changed: bool = false,
    font_changed: bool = false,
    colors_changed: bool = false,
};

pub fn reloadGlobal() ReloadResult {
    return .{};
}
