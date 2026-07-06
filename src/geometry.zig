const std = @import("std");

pub const Point = struct {
    x: i32,
    y: i32,

    pub const zero: Point = .{ .x = 0, .y = 0 };
};

pub const Size = u32;

pub const Rect = struct {
    x: i32,
    y: i32,
    width: Size,
    height: Size,

    pub const zero: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
};
