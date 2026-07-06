const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;
const wp = wayland.client.wp;
const ext = wayland.client.ext;

const Rect = @import("geometry.zig").Rect;
const color = @import("color.zig");

pub const CursorShape = wp.CursorShapeDeviceV1.Shape;

pub const max_outputs = 8;

pub const OutputIndex = enum(u8) {
    none = 0xFF,
    _0 = 0,
    _1,
    _2,
    _3,
    _4,
    _5,
    _6,
    _7,

    pub fn fromInt(idx: usize) OutputIndex {
        return @enumFromInt(@as(u8, @intCast(idx)));
    }

    pub fn toInt(self: OutputIndex) usize {
        return @intFromEnum(self);
    }
};

pub const OutputInfo = struct {
    output: *wl.Output,
    id: u32,
    scale: u31 = 1,
    physical_w: i32 = 0,
    physical_h: i32 = 0,
    mode_w: i32 = 0,
    mode_h: i32 = 0,
    name: [64]u8 = .{0} ** 64,
    has_mode: bool = false,
    has_name: bool = false,
    has_geo: bool = false,
    changed: bool = true,
};

pub const Context = struct {
    display: *wl.Display,
    registry: *wl.Registry,
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    layer_shell: ?*zwlr.LayerShellV1 = null,
    cursor_shape_manager: ?*wp.CursorShapeManagerV1 = null,
    foreign_toplevel: ?*zwlr.ForeignToplevelManagerV1 = null,
    workspace_manager: ?*ext.WorkspaceManagerV1 = null,
    seat: ?*wl.Seat = null,
    pointer: ?*wl.Pointer = null,
    keyboard: ?*wl.Keyboard = null,

    outputs: [max_outputs]OutputInfo = undefined,
    output_count: usize = 0,
    running: bool = true,

    last_motion_output: OutputIndex = .none,
    last_enter_serial: u32 = 0,
    last_cursor_shape: ?CursorShape = null,
    pointer_over_popup: bool = false,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, self: *Context) !void {
        const display = try wl.Display.connect(null);
        self.* = Context{
            .display = display,
            .registry = try display.getRegistry(),
            .allocator = allocator,
        };

        self.registry.setListener(*Context, registryListener, self);
        self.roundtrip();
    }

    pub fn deinit(self: *Context) void {
        self.display.disconnect();
    }

    pub fn roundtrip(self: *Context) void {
        _ = self.display.roundtrip();
    }

    pub fn flush(self: *Context) void {
        _ = self.display.flush();
    }

    pub fn dispatch(self: *Context) void {
        _ = self.display.dispatch();
    }

    pub fn getFd(self: *Context) i32 {
        return self.display.getFd();
    }

    pub fn findOutputByName(self: *Context, name: []const u8) ?*OutputInfo {
        for (0..self.output_count) |i| {
            const out = &self.outputs[i];
            const out_name = std.mem.sliceTo(&out.name, 0);
            if (std.mem.eql(u8, out_name, name)) return out;
        }
        return null;
    }

    pub fn findOutputBySurface(self: *Context, surface: *wl.Surface) ?*OutputInfo {
        _ = surface;
        _ = self;
        return null;
    }
};

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, ctx: *Context) void {
    switch (event) {
        .global => |global| {
            const iface = std.mem.span(global.interface);
            std.log.info("registry global: '{s}' ver={d}", .{ iface, global.version });
            if (std.mem.eql(u8, iface, std.mem.span(wl.Compositor.interface.name))) {
                ctx.compositor = registry.bind(global.name, wl.Compositor, global.version) catch null;
                std.log.info("  -> compositor={any}", .{ctx.compositor});
            } else if (std.mem.eql(u8, iface, std.mem.span(wl.Shm.interface.name))) {
                ctx.shm = registry.bind(global.name, wl.Shm, global.version) catch null;
                std.log.info("  -> shm={any}", .{ctx.shm});
            } else if (std.mem.eql(u8, iface, std.mem.span(zwlr.LayerShellV1.interface.name))) {
                ctx.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, @min(global.version, 5)) catch null;
                std.log.info("  -> layer_shell={any}", .{ctx.layer_shell});
            } else if (std.mem.eql(u8, iface, std.mem.span(wp.CursorShapeManagerV1.interface.name))) {
                ctx.cursor_shape_manager = registry.bind(global.name, wp.CursorShapeManagerV1, global.version) catch null;
            } else if (std.mem.eql(u8, iface, std.mem.span(zwlr.ForeignToplevelManagerV1.interface.name))) {
                ctx.foreign_toplevel = registry.bind(global.name, zwlr.ForeignToplevelManagerV1, global.version) catch null;
            } else if (std.mem.eql(u8, iface, std.mem.span(ext.WorkspaceManagerV1.interface.name))) {
                ctx.workspace_manager = registry.bind(global.name, ext.WorkspaceManagerV1, global.version) catch null;
            } else if (std.mem.eql(u8, iface, std.mem.span(wl.Seat.interface.name))) {
                ctx.seat = registry.bind(global.name, wl.Seat, @min(global.version, 8)) catch null;
                std.log.info("  -> seat={any}", .{ctx.seat});
            } else if (std.mem.eql(u8, iface, std.mem.span(wl.Output.interface.name))) {
                if (ctx.output_count < max_outputs) {
                    const output = registry.bind(global.name, wl.Output, global.version) catch null;
                    if (output) |o| {
                        const info = &ctx.outputs[ctx.output_count];
                        info.* = .{ .output = o, .id = global.name };
                        o.setListener(*Context, outputListener, ctx);
                        ctx.output_count += 1;
                        std.log.info("  -> output #{d} bound: info={*} output={any}", .{ ctx.output_count - 1, info, o });
                    } else {
                        std.log.warn("  -> output bind FAILED", .{});
                    }
                }
            } else {
                std.log.info("  -> ignored", .{});
            }
        },
        .global_remove => |remove| {
            _ = remove;
        },
    }
}

fn outputListener(output: *wl.Output, event: wl.Output.Event, ctx: *Context) void {
    std.log.info("outputListener: ctx.outputs[0].output={any} event_output={any} output_count={d}", .{
        if (ctx.output_count > 0) ctx.outputs[0].output else null,
        output,
        ctx.output_count,
    });
    const info = for (0..ctx.output_count) |i| {
        if (ctx.outputs[i].output == output) break &ctx.outputs[i];
    } else {
        std.log.warn("output event from unknown output", .{});
        return;
    };

    switch (event) {
        .geometry => |geo| {
            info.physical_w = geo.physical_width;
            info.physical_h = geo.physical_height;
            info.has_geo = true;
            info.changed = true;
            std.log.info("output geometry: {d}x{d} (info ptr={*})", .{ geo.physical_width, geo.physical_height, info });
        },
        .mode => |mode| {
            info.mode_w = mode.width;
            info.mode_h = mode.height;
            info.has_mode = true;
            info.changed = true;
            std.log.info("output mode: {d}x{d} -> info.mode_w={d}", .{ mode.width, mode.height, info.mode_w });
        },
        .name => |name_ev| {
            info.has_name = true;
            const name_src = std.mem.sliceTo(name_ev.name, 0);
            const name_len = @min(name_src.len, info.name.len - 1);
            @memcpy(info.name[0..name_len], name_src[0..name_len]);
            info.name[name_len] = 0;
            info.changed = true;
            std.log.info("output name: '{s}' info.name='{s}'", .{ name_src, std.mem.sliceTo(&info.name, 0) });
        },
        .scale => |scale_ev| {
            info.scale = @intCast(@max(1, scale_ev.factor));
            info.changed = true;
            std.log.info("output scale: {d}", .{scale_ev.factor});
        },
        .description, .done => {},
    }
}

pub const LayerSurface = struct {
    surface: *wl.Surface,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,
    frame_cb: ?*wl.Callback = null,
    configured: bool = false,
    width: i32 = 0,
    height: i32 = 0,

    pub fn create(ctx: *Context, output_info: *OutputInfo, anchor: zwlr.LayerSurfaceV1.Anchor, height: u32) !LayerSurface {
        const compositor = ctx.compositor orelse return error.NoCompositor;
        const layer_shell = ctx.layer_shell orelse return error.NoLayerShell;

        const surface = try compositor.createSurface();
        const layer = try layer_shell.getLayerSurface(
            surface,
            output_info.output,
            .top,
            "mist-bar",
        );

        layer.setSize(0, height);
        layer.setAnchor(anchor);
        layer.setExclusiveZone(@intCast(height));
        layer.setKeyboardInteractivity(.none);

        surface.commit();

        return LayerSurface{
            .surface = surface,
            .layer_surface = layer,
        };
    }

    pub fn requestFrame(self: *LayerSurface) void {
        if (self.frame_cb) |cb| cb.destroy();
        const cb = self.surface.frame() catch return;
        self.frame_cb = cb;
    }

    pub fn resize(self: *LayerSurface, height: u32) void {
        if (self.layer_surface) |ls| {
            ls.setSize(0, height);
            ls.setExclusiveZone(@intCast(height));
        }
    }

    pub fn destroy(self: *LayerSurface) void {
        if (self.frame_cb) |cb| cb.destroy();
        if (self.layer_surface) |ls| ls.destroy();
        self.surface.destroy();
        self.* = undefined;
    }
};

pub const DamageTracker = struct {
    full: bool = false,
    pending_full: bool = false,

    pub fn markFull(self: *DamageTracker) void {
        self.pending_full = true;
    }

    pub fn commit(self: *DamageTracker) void {
        self.full = self.pending_full;
        self.pending_full = false;
    }

    pub fn reset(self: *DamageTracker) void {
        self.full = false;
    }
};

pub const ShmBuffer = struct {
    buffer: ?*wl.Buffer = null,
    data: []align(std.heap.page_size_min) u8 = &.{},
    width: i32 = 0,
    height: i32 = 0,
    stride: i32 = 0,
    size: usize = 0,

    pub fn create(shm: *wl.Shm, w: i32, h: i32) !ShmBuffer {
        const raw_stride = w * 4;
        const stride = (raw_stride + 255) & ~@as(i32, 255);
        const pool_size = @as(usize, @intCast(stride * h));
        const fd = try createFile(pool_size);
        const pool = try shm.createPool(fd, @intCast(pool_size));
        const data = try std.posix.mmap(
            null,
            pool_size,
            std.posix.PROT{ .READ = true, .WRITE = true },
            std.posix.MAP{ .TYPE = .SHARED },
            fd,
            0,
        );
        _ = std.c.close(fd);

        @memset(data, 0);

        const buf = try pool.createBuffer(0, w, h, stride, wl.Shm.Format.argb8888);
        pool.destroy();

        return ShmBuffer{
            .buffer = buf,
            .data = data,
            .width = w,
            .height = h,
            .stride = stride,
            .size = pool_size,
        };
    }

    pub fn deinit(self: *ShmBuffer) void {
        std.posix.munmap(self.data);
        if (self.buffer) |b| b.destroy();
        self.* = undefined;
    }
};

fn createFile(size: usize) !i32 {
    const fd = try std.posix.memfd_create("wl-shm", 0);
    _ = std.c.ftruncate(fd, @intCast(size));
    return fd;
}
