const std = @import("std");
const rdr = @import("render.zig");
const Surface = rdr.Surface;
const Color = rdr.Color;
const geo = @import("../geo.zig");
const Rect = geo.Rect;
const Size = geo.Size;

const wayland_lib = @import("wayland");
const wl = wayland_lib.client.wl;
const zwlr = wayland_lib.client.zwlr;

pub const PopupType = enum { none, menu, tooltip };

pub const DrawFn = *const fn (surface: *Surface, size: geo.Point, ctx: ?*anyopaque) void;

pub const LayerPopup = struct {
    const Self = @This();

    compositor: *wl.Compositor,
    layer_shell: *zwlr.LayerShellV1,
    wl_shm: *wl.Shm,
    output: *wl.Output,
    surface: ?*wl.Surface = null,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,
    pool: ?rdr.DoubleShmPool = null,
    popup_type: PopupType = .none,
    bar_at_bottom: bool = false,
    visible: bool = false,
    configured: bool = false,
    width: Size = 0,
    height: Size = 0,
    frame_callback: ?*wl.Callback = null,
    last_pointer_pos: geo.Point = .{},
    scale: u31 = 1,
    serial: u32 = 0,

    pub const InitArgs = struct {
        wl_shm: *wl.Shm,
        compositor: *wl.Compositor,
        layer_shell: *zwlr.LayerShellV1,
        output: *wl.Output,
        bar_at_bottom: bool,
    };

    pub fn init(args: InitArgs) Self {
        return .{
            .compositor = args.compositor,
            .layer_shell = args.layer_shell,
            .wl_shm = args.wl_shm,
            .output = args.output,
            .bar_at_bottom = args.bar_at_bottom,
        };
    }

    pub fn deinit(self: *Self) void {
        self.hide();
        if (self.pool) |*p| p.deinit();
        if (self.layer_surface) |ls| ls.destroy();
        if (self.surface) |s| s.destroy();
        if (self.frame_callback) |fc| fc.destroy();
    }

    pub fn showCentered(
        self: *Self,
        popup_type: PopupType,
        center_x: i32,
        _: i32,
        width: Size,
        height: Size,
        screen_width: Size,
        scale: u31,
        draw_fn: DrawFn,
        draw_ctx: ?*anyopaque,
    ) !void {
        self.popup_type = popup_type;
        self.scale = scale;

        if (self.surface == null) {
            self.surface = try self.compositor.createSurface();
            self.layer_surface = try self.layer_shell.getLayerSurface(
                self.surface.?,
                self.output,
                .overlay,
                "mist-popup",
            );
            self.layer_surface.?.setKeyboardInteractivity(.exclusive);
            self.layer_surface.?.setListener(*Self, popupLayerListener, self);
        }

        self.width = width;
        self.height = height;

        var x = center_x -| (width / 2);
        if (x + width > screen_width) x = screen_width -| width;

        self.layer_surface.?.setSize(width, height);
        self.layer_surface.?.setAnchor(.{ .top = true, .left = true });
        self.layer_surface.?.setExclusiveZone(-1);
        self.layer_surface.?.setMargin(x, 0, 0, 0);

        if (self.bar_at_bottom) {
            self.layer_surface.?.setAnchor(.{ .bottom = true, .left = true });
        }

        self.surface.?.commit();
        self.visible = true;

        self.drawPopup(draw_fn, draw_ctx);
    }

    pub fn hide(self: *Self) void {
        if (self.layer_surface) |ls| {
            ls.destroy();
            self.layer_surface = null;
        }
        if (self.surface) |s| {
            s.destroy();
            self.surface = null;
        }
        if (self.pool) |*p| {
            p.deinit();
            self.pool = null;
        }
        if (self.frame_callback) |fc| {
            fc.destroy();
            self.frame_callback = null;
        }
        self.visible = false;
        self.configured = false;
        self.popup_type = .none;
    }

    pub fn isVisible(self: *const Self) bool {
        return self.visible;
    }

    pub fn getBounds(self: *const Self) Rect {
        return .{ .x = 0, .y = 0, .width = self.width, .height = self.height };
    }

    pub fn isActiveAndConfigured(self: *const Self) bool {
        return self.visible and self.configured;
    }

    pub fn getPopupType(self: *const Self) PopupType {
        return self.popup_type;
    }

    pub fn requestRedraw(self: *Self) void {
        if (self.frame_callback != null) return;
        if (self.surface == null or !self.configured) return;
        self.frame_callback = self.surface.?.frame() catch return;
        self.frame_callback.?.setListener(*Self, popupFrameListener, self);
        self.surface.?.commit();
    }

    fn drawPopup(self: *Self, draw_fn: DrawFn, draw_ctx: ?*anyopaque) void {
        const w = self.width;
        const h = self.height;
        const s = self.scale;

        if (w == 0 or h == 0) return;

        if (self.pool == null) {
            self.pool = rdr.DoubleShmPool.init(self.wl_shm, w, h, s) catch return;
            self.pool.?.bindReleaseListeners();
        }
        if (self.pool.?.width != w or self.pool.?.height != h or self.pool.?.scale != s) {
            self.pool.?.resize(w, h, s) catch return;
        }

        const acquired = self.pool.?.acquire() orelse return;
        var surf = rdr.Surface.fromPixelsScaledWithStride(
            acquired.pixels,
            w * s,
            h * s,
            acquired.stride_pixels,
            s,
        );
        surf.clear(Color.transparent);

        const size = geo.Point{ .x = @intCast(w), .y = @intCast(h) };
        draw_fn(&surf, size, draw_ctx);

        self.surface.?.attach(acquired.wl_buffer, 0, 0);
        self.surface.?.damageBuffer(0, 0, @intCast(w * s), @intCast(h * s));
        self.surface.?.commit();
    }

    fn popupLayerListener(_: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, self: *Self) void {
        switch (event) {
            .configure => |cfg| {
                self.serial = cfg.serial;
                self.configured = true;
                self.layer_surface.?.ackConfigure(cfg.serial);
            },
            .closed => {
                self.visible = false;
                self.configured = false;
            },
        }
    }

    fn popupFrameListener(_: *wl.Callback, _: wl.Callback.Event, _: *Self) void {}
};
