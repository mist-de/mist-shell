const std = @import("std");

pub fn BoundedArray(comptime T: type, comptime max_capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [max_capacity]T = undefined,
        len: usize = 0,

        pub fn capacity(_: *const Self) usize {
            return max_capacity;
        }

        pub fn slice(self: *const Self) []const T {
            return self.buffer[0..self.len];
        }

        pub fn constSlice(self: *const Self) []const T {
            return self.buffer[0..self.len];
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len >= max_capacity) return error.OutOfMemory;
            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn orderedRemove(self: *Self, index: usize) T {
            const item = self.buffer[index];
            if (index + 1 < self.len) {
                std.mem.copyForwards(T, self.buffer[index..], self.buffer[index + 1 .. self.len]);
            }
            self.len -= 1;
            return item;
        }
    };
}
