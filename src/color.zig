pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const white: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toPixel(self: Color) u32 {
        if (self.a == 0) return 0;
        if (self.a == 255) {
            return 0xFF000000 |
                @as(u32, @intCast(self.r)) << 16 |
                @as(u32, @intCast(self.g)) << 8 |
                @as(u32, @intCast(self.b));
        }
        const a = @as(u32, self.a);
        return (a << 24) |
            (@as(u32, self.r) * a / 255 << 16) |
            (@as(u32, self.g) * a / 255 << 8) |
            (@as(u32, self.b) * a / 255);
    }

    pub fn fromPixel(pixel: u32) Color {
        return .{
            .r = @intCast((pixel >> 16) & 0xFF),
            .g = @intCast((pixel >> 8) & 0xFF),
            .b = @intCast(pixel & 0xFF),
            .a = @intCast((pixel >> 24) & 0xFF),
        };
    }
};
