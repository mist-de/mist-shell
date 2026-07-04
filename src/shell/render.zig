const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const posix = std.posix;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const BoundedArray = @import("bounded_array.zig").BoundedArray;

pub const stride_alignment: usize = 256;
pub const default_buffer_count: usize = 2;

pub const ShmLayout = struct {
    physical_width: u31,
    physical_height: u31,
    stride_bytes: u31,
    stride_pixels: u31,
    visible_bytes: usize,
    slot_bytes: usize,
    total_bytes: usize,

    pub fn bufferOffset(self: ShmLayout, index: usize) usize {
        return self.slot_bytes * index;
    }
};

pub fn computeShmLayout(width: u32, height: u32, scale: u32, comptime buf_count: usize) !ShmLayout {
    const pw = try mulU31(width, scale);
    const ph = try mulU31(height, scale);
    const tight = try mulU31(pw, 4);
    const sb = mem.alignForward(usize, tight, stride_alignment);
    if (sb > std.math.maxInt(u31)) return error.Overflow;
    const stride: u31 = @intCast(sb);
    const sp: u31 = @intCast(sb / 4);
    const vis = try mulUsize(sb, ph);
    const slot = mem.alignForward(usize, vis, heap.page_size_min);
    const total = try mulUsize(slot, buf_count);
    return .{
        .physical_width = pw,
        .physical_height = ph,
        .stride_bytes = stride,
        .stride_pixels = sp,
        .visible_bytes = vis,
        .slot_bytes = slot,
        .total_bytes = total,
    };
}

fn mulU31(a: u32, b: u32) !u31 {
    const r = @as(u64, a) * @as(u64, b);
    if (r > std.math.maxInt(u31)) return error.Overflow;
    return @intCast(r);
}

fn mulUsize(a: usize, b: usize) !usize {
    const r = @mulWithOverflow(a, b);
    if (r[1] != 0) return error.Overflow;
    return r[0];
}

pub const Color = packed struct(u32) {
    b: u8 = 0,
    g: u8 = 0,
    r: u8 = 0,
    a: u8 = 0,

    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const white: Color = .{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0xff };

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn blend(base: Color, overlay: Color, ratio: u8) Color {
        const inv = 255 - ratio;
        return .{
            .r = @truncate((@as(u32, base.r) * inv + @as(u32, overlay.r) * ratio) / 255),
            .g = @truncate((@as(u32, base.g) * inv + @as(u32, overlay.g) * ratio) / 255),
            .b = @truncate((@as(u32, base.b) * inv + @as(u32, overlay.b) * ratio) / 255),
            .a = @truncate((@as(u32, base.a) * inv + @as(u32, overlay.a) * ratio) / 255),
        };
    }

    pub fn withAlpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }
};

pub const Surface = struct {
    pixels: []Color,
    width: u32,
    height: u32,
    stride_pixels: u32,
    scale: u32,

    pub fn fromPixelsScaledWithStride(pixels: []Color, width: u32, height: u32, stride_pixels: u32, scale: u32) Surface {
        return .{ .pixels = pixels, .width = width, .height = height, .stride_pixels = stride_pixels, .scale = scale };
    }

    pub fn clear(self: *Surface, color: Color) void {
        for (self.pixels) |*p| p.* = color;
    }

    pub fn fillRect(self: *Surface, x: i32, y: i32, w: u32, h: u32, color: Color) void {
        const sx = @max(x, 0);
        const sy = @max(y, 0);
        const ex = @min(@as(i32, @intCast(self.width)), x + @as(i32, @intCast(w)));
        const ey = @min(@as(i32, @intCast(self.height)), y + @as(i32, @intCast(h)));
        var row = sy;
        while (row < ey) : (row += 1) {
            const line_start = @as(usize, @intCast(row)) * self.stride_pixels;
            var col = sx;
            while (col < ex) : (col += 1) {
                self.pixels[line_start + @as(usize, @intCast(col))] = color;
            }
        }
    }

    pub fn fillRectLogical(self: *Surface, rect: Rect, color: Color) void {
        self.fillRect(rect.x, rect.y, rect.width, rect.height, color);
    }

    pub fn fillRoundedRect(self: *Surface, x: i32, y: i32, w: u32, h: u32, radius: u32, color: Color) void {
        if (radius == 0) {
            self.fillRect(x, y, w, h, color);
            return;
        }
        const sx = @max(x, 0);
        const sy = @max(y, 0);
        const ex = @min(@as(i32, @intCast(self.width)), x + @as(i32, @intCast(w)));
        const ey = @min(@as(i32, @intCast(self.height)), y + @as(i32, @intCast(h)));
        const r2 = @as(i32, @intCast(radius * radius));
        const x_i: i32 = @intCast(x);
        const y_i: i32 = @intCast(y);
        const w_i: i32 = @intCast(w);
        const h_i: i32 = @intCast(h);
        const r_i: i32 = @intCast(radius);
        const cx_tl = x_i + r_i;
        const cy_tl = y_i + r_i;
        const cx_tr = x_i + w_i - r_i - 1;
        const cy_tr = cy_tl;
        const cx_bl = cx_tl;
        const cy_bl = y_i + h_i - r_i - 1;
        const cx_br = cx_tr;
        const cy_br = cy_bl;
        var row = sy;
        while (row < ey) : (row += 1) {
            const line_start = @as(usize, @intCast(row)) * self.stride_pixels;
            var col = sx;
            while (col < ex) : (col += 1) {
                var inside = true;
                if (row < cy_tl) {
                    if (col < cx_tl) {
                        const dx = col - cx_tl;
                        const dy = row - cy_tl;
                        if (dx * dx + dy * dy > r2) inside = false;
                    } else if (col > cx_tr) {
                        const dx = col - cx_tr;
                        const dy = row - cy_tr;
                        if (dx * dx + dy * dy > r2) inside = false;
                    }
                } else if (row > cy_bl) {
                    if (col < cx_bl) {
                        const dx = col - cx_bl;
                        const dy = row - cy_bl;
                        if (dx * dx + dy * dy > r2) inside = false;
                    } else if (col > cx_br) {
                        const dx = col - cx_br;
                        const dy = row - cy_br;
                        if (dx * dx + dy * dy > r2) inside = false;
                    }
                }
                if (inside) {
                    self.pixels[line_start + @as(usize, @intCast(col))] = color;
                }
            }
        }
    }

    pub fn fillRoundedRectLogical(self: *Surface, rect: Rect, radius: u32, color: Color) void {
        self.fillRoundedRect(rect.x, rect.y, rect.width, rect.height, radius, color);
    }

    pub fn setPixel(self: *Surface, x: i32, y: i32, color: Color) void {
        if (x < 0 or y < 0) return;
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        if (ux >= self.width or uy >= self.height) return;
        self.pixels[@as(usize, uy) * self.stride_pixels + ux] = color;
    }

    pub fn getPixel(self: *Surface, x: i32, y: i32) Color {
        if (x < 0 or y < 0) return .{};
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        if (ux >= self.width or uy >= self.height) return .{};
        return self.pixels[@as(usize, uy) * self.stride_pixels + ux];
    }
};

fn createMemfd(name: [:0]const u8) !posix.fd_t {
    const flags = [_]u32{ std.os.linux.MFD.HUGE_1MB | std.os.linux.MFD.CLOEXEC, std.os.linux.MFD.CLOEXEC };
    for (flags) |f| {
        return posix.memfd_createZ(name, f) catch |err| switch (err) {
            error.NameTooLong => continue,
            else => return err,
        };
    }
    unreachable;
}

fn truncateFd(fd: posix.fd_t, size: usize) !void {
    const rc = std.posix.system.ftruncate(fd, @intCast(size));
    switch (std.posix.errno(rc)) {
        .SUCCESS => return,
        .INTR => return error.Unexpected,
        .NOSPC => return error.NoSpaceLeft,
        .IO => return error.InputOutput,
        else => return error.Unexpected,
    }
}

fn mapColors(fd: posix.fd_t, size: usize) ![]align(heap.page_size_min) Color {
    const mapped = try posix.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
    const ptr: [*]align(heap.page_size_min) Color = @ptrCast(mapped.ptr);
    return ptr[0 .. size / @sizeOf(Color)];
}

fn unmapColors(buf: []align(heap.page_size_min) Color) void {
    const bytes: [*]align(heap.page_size_min) u8 = @ptrCast(buf.ptr);
    posix.munmap(bytes[0 .. buf.len * @sizeOf(Color)]);
}

pub const DoubleShmPool = struct {
    const Self = @This();

    pub const Acquired = struct {
        wl_buffer: *wl.Buffer,
        pixels: []Color,
        stride_pixels: u32,
        index: u8,
    };

    wl_pool: *wl.ShmPool,
    fd: posix.fd_t,
    memory: []align(heap.page_size_min) Color,
    memory_len: usize,
    buffers: [2]BufferSlot,
    width: u32,
    height: u32,
    scale: u32,

    const BufferSlot = struct {
        wl_buffer: *wl.Buffer,
        pixels: []Color,
        stride_pixels: u32,
        index: u8,
        free: bool,
    };

    pub fn init(wl_shm: *wl.Shm, width: u32, height: u32, scale: u32) !Self {
        const layout = try computeShmLayout(width, height, scale, 2);
        const fd = try createMemfd("mist-shm");
        errdefer _ = posix.system.close(fd);
        try truncateFd(fd, layout.total_bytes);
        const memory = try mapColors(fd, layout.total_bytes);
        errdefer unmapColors(memory);
        const wl_pool = try wl_shm.createPool(fd, @intCast(layout.total_bytes));
        errdefer wl_pool.destroy();

        var buffers: [2]BufferSlot = undefined;
        for (0..2) |i| {
            const off = layout.bufferOffset(i);
            const buf = try wl_pool.createBuffer(
                @intCast(off),
                @intCast(layout.physical_width),
                @intCast(layout.physical_height),
                @intCast(layout.stride_bytes),
                .argb8888,
            );
            const start = off / @sizeOf(Color);
            const count = layout.stride_pixels * layout.physical_height;
            buffers[i] = .{
                .wl_buffer = buf,
                .pixels = memory[start..][0..count],
                .stride_pixels = layout.stride_pixels,
                .index = @intCast(i),
                .free = true,
            };
        }

        return .{
            .wl_pool = wl_pool,
            .fd = fd,
            .memory = memory,
            .memory_len = layout.total_bytes,
            .buffers = buffers,
            .width = width,
            .height = height,
            .scale = scale,
        };
    }

    pub fn deinit(self: *Self) void {
        for (&self.buffers) |*b| b.wl_buffer.destroy();
        self.wl_pool.destroy();
        _ = posix.system.close(self.fd);
        unmapColors(self.memory);
    }

    pub fn bindReleaseListeners(self: *Self) void {
        for (&self.buffers) |*b| {
            b.free = true;
            b.wl_buffer.setListener(*BufferSlot, releaseListener, b);
        }
    }

    fn releaseListener(_: *wl.Buffer, event: wl.Buffer.Event, slot: *BufferSlot) void {
        switch (event) {
            .release => slot.free = true,
        }
    }

    pub fn acquire(self: *Self) ?Acquired {
        for (&self.buffers) |*b| {
            if (b.free) {
                b.free = false;
                return .{
                    .wl_buffer = b.wl_buffer,
                    .pixels = b.pixels,
                    .stride_pixels = b.stride_pixels,
                    .index = b.index,
                };
            }
        }
        return null;
    }

    pub fn allFree(self: *const Self) bool {
        for (&self.buffers) |b| {
            if (!b.free) return false;
        }
        return true;
    }

    pub fn resize(self: *Self, width: u32, height: u32, scale: u32) !void {
        const layout = try computeShmLayout(width, height, scale, 2);
        if (!self.allFree()) return error.BuffersBusy;
        for (&self.buffers) |*b| b.wl_buffer.destroy();
        if (layout.total_bytes > self.memory_len) {
            unmapColors(self.memory);
            try truncateFd(self.fd, layout.total_bytes);
            self.memory = try mapColors(self.fd, layout.total_bytes);
            self.memory_len = layout.total_bytes;
            self.wl_pool.resize(@intCast(layout.total_bytes));
        }
        self.width = width;
        self.height = height;
        self.scale = scale;
        for (0..2) |i| {
            const off = layout.bufferOffset(i);
            const buf = try self.wl_pool.createBuffer(
                @intCast(off),
                @intCast(layout.physical_width),
                @intCast(layout.physical_height),
                @intCast(layout.stride_bytes),
                .argb8888,
            );
            const start = off / @sizeOf(Color);
            const count = layout.stride_pixels * layout.physical_height;
            self.buffers[i] = .{
                .wl_buffer = buf,
                .pixels = self.memory[start..][0..count],
                .stride_pixels = layout.stride_pixels,
                .index = @intCast(i),
                .free = true,
            };
            buf.setListener(*BufferSlot, releaseListener, &self.buffers[i]);
        }
    }
};

pub const Renderer = struct {
    const Self = @This();

    pool: DoubleShmPool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, wl_shm: *wl.Shm, width: u32, height: u32, scale: u32) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .pool = try DoubleShmPool.init(wl_shm, width, height, scale),
            .allocator = allocator,
        };
        self.pool.bindReleaseListeners();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.pool.deinit();
        self.allocator.destroy(self);
    }

    pub fn resize(self: *Self, width: u32, height: u32, scale: u32) !void {
        try self.pool.resize(width, height, scale);
    }

    pub fn acquire(self: *Self) ?AcquiredFrame {
        const a = self.pool.acquire() orelse return null;
        return .{
            .surface = Surface.fromPixelsScaledWithStride(
                a.pixels,
                self.pool.width * self.pool.scale,
                self.pool.height * self.pool.scale,
                a.stride_pixels,
                self.pool.scale,
            ),
            .wl_buffer = a.wl_buffer,
            .renderer = self,
            .index = a.index,
        };
    }

    pub const AcquiredFrame = struct {
        surface: Surface,
        wl_buffer: *wl.Buffer,
        renderer: *Renderer,
        index: u8,

        pub fn release(_: *AcquiredFrame) void {}

        pub fn submit(self: *AcquiredFrame, wl_surface: *wl.Surface, damage_tracker: *const DamageTracker) void {
            wl_surface.attach(self.wl_buffer, 0, 0);
            if (damage_tracker.isFull()) {
                wl_surface.damageBuffer(0, 0, @intCast(self.surface.width), @intCast(self.surface.height));
            } else {
                for (damage_tracker.effectiveRects()) |r| {
                    wl_surface.damageBuffer(r.x, r.y, @intCast(r.width), @intCast(r.height));
                }
            }
            wl_surface.commit();
        }
    };
};

pub const Rect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn intersects(a: Rect, b: Rect) bool {
        if (a.x >= b.x + @as(i32, @intCast(b.width))) return false;
        if (b.x >= a.x + @as(i32, @intCast(a.width))) return false;
        if (a.y >= b.y + @as(i32, @intCast(b.height))) return false;
        if (b.y >= a.y + @as(i32, @intCast(a.height))) return false;
        return true;
    }

    pub fn containsPoint(r: Rect, px: i32, py: i32) bool {
        return px >= r.x and py >= r.y and
            px < r.x + @as(i32, @intCast(r.width)) and
            py < r.y + @as(i32, @intCast(r.height));
    }
};

pub const DamageTracker = struct {
    const Self = @This();
    const max_rects = 64;

    rects: BoundedArray(Rect, max_rects) = .{},
    full_damage: bool = true,
    prev_rects: BoundedArray(Rect, max_rects) = .{},
    prev_full_damage: bool = true,

    pub fn reset(self: *Self) void {
        self.rects.len = 0;
        self.full_damage = false;
    }

    pub fn addRect(self: *Self, r: Rect) void {
        if (self.full_damage) return;
        if (r.width == 0 or r.height == 0) return;
        self.rects.append(r) catch {
            self.full_damage = true;
        };
    }

    pub fn markFullDamage(self: *Self) void {
        self.full_damage = true;
        self.rects.len = 0;
    }

    pub fn commitFrame(self: *Self) void {
        self.prev_rects = self.rects;
        self.prev_full_damage = self.full_damage;
        self.rects.len = 0;
        self.full_damage = false;
    }

    pub fn hasDamage(self: *const Self) bool {
        return self.full_damage or self.rects.len > 0;
    }

    pub fn isFull(self: *const Self) bool {
        return self.full_damage or self.prev_full_damage;
    }

    pub fn getEffectiveDamage(self: *const Self) struct { full: bool, rects: BoundedArray(Rect, max_rects) } {
        var combined: BoundedArray(Rect, max_rects) = .{};
        for (self.rects.constSlice()) |r| combined.append(r) catch {};
        for (self.prev_rects.constSlice()) |r| combined.append(r) catch {};
        return .{ .full = self.full_damage or self.prev_full_damage, .rects = combined };
    }

    pub fn effectiveRects(self: *const Self) []const Rect {
        if (self.full_damage or self.prev_full_damage) return &.{};
        return self.rects.constSlice();
    }
};
