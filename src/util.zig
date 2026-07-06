const std = @import("std");

pub fn BoundedArray(comptime T: type, comptime max_size: usize) type {
    return struct {
        const Self = @This();

        data: [max_size]T = undefined,
        len: usize = 0,

        pub fn append(self: *Self, item: T) !void {
            if (self.len >= max_size) return error.OutOfMemory;
            self.data[self.len] = item;
            self.len += 1;
        }

        pub fn slice(self: *Self) []T {
            return self.data[0..self.len];
        }

        pub fn constSlice(self: *const Self) []const T {
            return self.data[0..self.len];
        }

        pub fn reset(self: *Self) void {
            self.len = 0;
        }
    };
}

pub fn format(comptime fmt: []const u8, args: anytype) ![256]u8 {
    var buf: [256]u8 = undefined;
    _ = try std.fmt.bufPrint(&buf, fmt, args);
    return buf;
}
