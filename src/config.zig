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

fn fileExists(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes + 1]u8 = undefined;
    if (path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(&buf);
    return std.c.access(path_z, std.c.F_OK) == 0;
}

pub fn resolveFontPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    // 1. fonts/ relative to CWD
    const cwd_path = try std.fs.path.join(allocator, &.{ "fonts", name });
    if (fileExists(cwd_path)) return cwd_path;
    allocator.free(cwd_path);

    // 2. zig-out/fonts/ relative to CWD
    const zig_out = try std.fs.path.join(allocator, &.{ "zig-out", "fonts", name });
    if (fileExists(zig_out)) return zig_out;
    allocator.free(zig_out);

    // 3. ~/.fonts/
    if (std.c.getenv("HOME")) |home_ptr| {
        const home = std.mem.span(home_ptr);
        const home_path = try std.fs.path.join(allocator, &.{ home, ".fonts", name });
        if (fileExists(home_path)) return home_path;
        allocator.free(home_path);
    }

    // 4. Fallback (will fail at FT_New_Face)
    return std.fs.path.join(allocator, &.{ "fonts", name });
}

pub fn reload(allocator: std.mem.Allocator) void {
    _ = allocator;
}
