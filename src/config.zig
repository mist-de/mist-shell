const std = @import("std");

pub const Colors = struct {
    background: [4]u8 = .{ 0x14, 0x13, 0x13, 0xFF },
    foreground: [4]u8 = .{ 0xe6, 0xe1, 0xe1, 0xFF },
    accent: [4]u8 = .{ 0xcb, 0xa6, 0xf7, 0xFF },
    widget_bg: [4]u8 = .{ 0x1c, 0x1b, 0x1c, 0xFF },
    urgent: [4]u8 = .{ 0xf3, 0x8b, 0xa8, 0xFF },
};

pub const Config = struct {
    height: u32 = 40,
    bottom: bool = false,
    font_regular: []const u8 = "Inter_18pt-Regular.ttf",
    font_bold: []const u8 = "Inter_18pt-Bold.ttf",
    font_icon: []const u8 = "NotoSansNerdFont-Regular.ttf",
    font_material: []const u8 = "MaterialSymbolsRounded.ttf",
    font_size: u32 = 15,
    font_size_large: u32 = 17,
    colors: Colors = .{},
};

var global_config: Config = .{};

pub fn get() *const Config {
    return &global_config;
}

pub fn getMut() *Config {
    return &global_config;
}

pub fn resolveFontPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ "fonts", name });
}

pub fn reload(allocator: std.mem.Allocator) void {
    _ = allocator;
}
