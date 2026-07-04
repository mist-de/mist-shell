const std = @import("std");

pub const Coord = i32;
pub const Size = u32;
pub const SizeSigned = i32;

pub const Point = struct {
    x: Coord = 0,
    y: Coord = 0,

    pub const zero: Point = .{};
};

pub const Rect = struct {
    x: Coord = 0,
    y: Coord = 0,
    width: Size = 0,
    height: Size = 0,

    pub const zero: Rect = .{};

    pub fn containsPoint(self: Rect, p: Point) bool {
        return p.x >= self.x and p.y >= self.y and
            p.x < self.x + @as(Coord, @intCast(self.width)) and
            p.y < self.y + @as(Coord, @intCast(self.height));
    }

    pub fn intersects(a: Rect, b: Rect) bool {
        if (a.x >= b.x + @as(Coord, @intCast(b.width))) return false;
        if (b.x >= a.x + @as(Coord, @intCast(a.width))) return false;
        if (a.y >= b.y + @as(Coord, @intCast(b.height))) return false;
        if (b.y >= a.y + @as(Coord, @intCast(a.height))) return false;
        return true;
    }
};

pub const Padding = struct {
    top: Size = 0,
    right: Size = 0,
    bottom: Size = 0,
    left: Size = 0,

    pub fn uniform(v: Size) Padding {
        return .{ .top = v, .right = v, .bottom = v, .left = v };
    }

    pub fn horizontal(self: Padding) Size {
        return self.left + self.right;
    }

    pub fn vertical(self: Padding) Size {
        return self.top + self.bottom;
    }
};
