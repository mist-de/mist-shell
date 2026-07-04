const rdr = @import("shell/render.zig");
const Color = rdr.Color;

pub const Theme = @This();

pub const default = Theme{};

bar: struct {
    height: u16 = 38,
    padding: u16 = 8,
    layout_padding: u16 = 4,
    background: Color = .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x00 },
    foreground: Color = .{ .r = 0xcd, .g = 0xd6, .b = 0xf4, .a = 0xff },
    item_background: Color = .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x00 },
    item_active_text: Color = .{ .r = 0x1e, .g = 0x1e, .b = 0x2e, .a = 0xff },
    group_background: Color = .{ .r = 0x18, .g = 0x18, .b = 0x25, .a = 0x30 },
    group_border: Color = .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x00 },
    border: Color = .{ .r = 0x31, .g = 0x32, .b = 0x44, .a = 0x60 },
} = .{},

colors: struct {
    background: Color = .{ .r = 0x1e, .g = 0x1e, .b = 0x2e, .a = 0xff },
    foreground: Color = .{ .r = 0xcd, .g = 0xd6, .b = 0xf4, .a = 0xff },
    accent: Color = .{ .r = 0x89, .g = 0xb4, .b = 0xfa, .a = 0xff },
    urgent: Color = .{ .r = 0xf3, .g = 0x8b, .b = 0xa8, .a = 0xff },
    success: Color = .{ .r = 0xa6, .g = 0xe3, .b = 0xa1, .a = 0xff },
    warning: Color = .{ .r = 0xf9, .g = 0xe2, .b = 0xaf, .a = 0xff },
    critical: Color = .{ .r = 0xf3, .g = 0x8b, .b = 0xa8, .a = 0xff },
    muted: Color = .{ .r = 0x6c, .g = 0x70, .b = 0x86, .a = 0xff },
    surface0: Color = .{ .r = 0x31, .g = 0x32, .b = 0x44, .a = 0xff },
    surface1: Color = .{ .r = 0x45, .g = 0x45, .b = 0x5a, .a = 0xff },
    overlay0: Color = .{ .r = 0x6c, .g = 0x70, .b = 0x86, .a = 0xff },
    blue: Color = .{ .r = 0x89, .g = 0xb4, .b = 0xfa, .a = 0xff },
    green: Color = .{ .r = 0xa6, .g = 0xe3, .b = 0xa1, .a = 0xff },
    yellow: Color = .{ .r = 0xf9, .g = 0xe2, .b = 0xaf, .a = 0xff },
    red: Color = .{ .r = 0xf3, .g = 0x8b, .b = 0xa8, .a = 0xff },
    teal: Color = .{ .r = 0x94, .g = 0xe2, .b = 0xd5, .a = 0xff },
    mauve: Color = .{ .r = 0xca, .g = 0x9e, .b = 0xe6, .a = 0xff },
    peach: Color = .{ .r = 0xfa, .g = 0xb3, .b = 0x87, .a = 0xff },
    sky: Color = .{ .r = 0x89, .g = 0xde, .b = 0xeb, .a = 0xff },
    sapphire: Color = .{ .r = 0x74, .g = 0xc7, .b = 0xec, .a = 0xff },
    maroon: Color = .{ .r = 0xeb, .g = 0xbc, .b = 0xb9, .a = 0xff },
    rosewater: Color = .{ .r = 0xf5, .g = 0xc2, .b = 0xe7, .a = 0xff },
} = .{},

fonts: struct {
    font_family: ?[]const u8 = null,
    size: f32 = 14,
} = .{},

popup: struct {
    background: Color = .{ .r = 0x1e, .g = 0x1e, .b = 0x2e, .a = 0xf0 },
    text: Color = .{ .r = 0xcd, .g = 0xd6, .b = 0xf4, .a = 0xff },
    border: Color = .{ .r = 0x45, .g = 0x45, .b = 0x5a, .a = 0xff },
    highlight: Color = .{ .r = 0x45, .g = 0x45, .b = 0x5a, .a = 0xff },
    selected: Color = .{ .r = 0x89, .g = 0xb4, .b = 0xfa, .a = 0xff },
    disabled: Color = .{ .r = 0x58, .g = 0x5b, .b = 0x70, .a = 0xff },
    separator: Color = .{ .r = 0x31, .g = 0x32, .b = 0x44, .a = 0xff },
    padding: u8 = 12,
    item_height: u16 = 28,
    border_width: u8 = 1,
    border_radius: u8 = 8,
} = .{},

surfaces: struct {
    recessed: Color = .{ .r = 0x18, .g = 0x18, .b = 0x25, .a = 0x40 },
    surface_alt: Color = .{ .r = 0x18, .g = 0x18, .b = 0x25, .a = 0x70 },
    hover: Color = .{ .r = 0x31, .g = 0x32, .b = 0x44, .a = 0x80 },
    pressed: Color = .{ .r = 0x45, .g = 0x45, .b = 0x5a, .a = 0x80 },
    border_subtle: Color = .{ .r = 0x31, .g = 0x32, .b = 0x44, .a = 0x80 },
    focus_ring: Color = .{ .r = 0x89, .g = 0xb4, .b = 0xfa, .a = 0xff },
} = .{},

spacing: struct {
    widget_h_padding: u8 = 8,
    widget_border_radius: u8 = 6,
    widget_padding: u8 = 6,
    icon_size: u8 = 14,
} = .{},

density: struct {
    panel_radius: u8 = 0,
} = .{},

pub fn panelColor(_: *const Theme, color: Color) Color {
    return color;
}

pub fn popupColor(_: *const Theme, color: Color) Color {
    return color;
}

pub fn widgetColor(_: *const Theme, color: Color) Color {
    return color;
}
