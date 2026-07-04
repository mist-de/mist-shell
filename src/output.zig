const std = @import("std");
const assert = std.debug.assert;

const geo = @import("geo.zig");
const rdr = @import("shell/render.zig");
const Wayland = @import("wayland.zig");
const wl = Wayland.wl;
const zwlr = Wayland.zwlr;

const Config = @import("config.zig");
const RootContainer = @import("components/root_container.zig");

const Point = geo.Point;
const Rect = geo.Rect;
const Size = geo.Size;
const Color = rdr.Color;

const log = std.log.scoped(.Output);

pub const Output = @This();

pub const NAME_STR_LEN = 64;

pub const MINIMUM_WIDTH: u16 = 500;
pub const MINIMUM_HEIGHT: u16 = 15;

pub const OutputContext = struct {
    output: *wl.Output,
    id: u32,
    has_mode: bool = false,
    screen_height: Size = 0,
    screen_width: Size = 0,
    refresh_mhz: u32 = 0,
    has_geometry: bool = false,
    physical_height: Size = 0,
    physical_width: Size = 0,
    has_name: bool = false,
    name_buf: [NAME_STR_LEN]u8 = undefined,
    name_len: usize = 0,
    changed: bool = true,
};

output_context: OutputContext,
root_container: ?RootContainer = null,
wayland_context: *Wayland,
full_redraw: bool = true,
surface: ?*wl.Surface = null,
layer_surface: ?*zwlr.LayerSurfaceV1 = null,
renderer: ?*rdr.Renderer = null,
damage_tracker: rdr.DamageTracker = .{},
frame_callback: ?*wl.Callback = null,
window_size: Point = .{ .x = 0, .y = 0 },
last_frame_time: i128 = 0,
popup: ?LayerPopup = null,
scale: u31 = 1,
pending_scale: u31 = 1,
ui_state: BarUiState = .{},

pub const BarUiState = UiState;

pub const UiState = struct {
    // Placeholder — will be expanded in Phase 2.4
    _dummy: u8 = 0,

    pub fn begin(_: *UiState, _: anytype) DummyFrame {
        return .{};
    }
};

pub const DummyFrame = struct {
    pub fn render(_: *DummyFrame, _: anytype, _: Rect) !void {}
    pub fn finish(_: *DummyFrame) void {}
};

pub const InitArgs = struct {
    output: *wl.Output,
    id: u32,
    wayland_context: *Wayland,
};

pub fn init(args: InitArgs) !Output {
    args.output.setListener(*Wayland, outputListener, args.wayland_context);

    return Output{
        .output_context = .{
            .output = args.output,
            .id = args.id,
        },
        .wayland_context = args.wayland_context,
    };
}

pub fn deinit(self: *Output) void {
    self.output_context.output.destroy();
    if (self.root_container) |*rc| rc.deinit();
    if (self.popup) |*p| p.deinit();
    if (self.renderer) |renderer| {
        renderer.deinit();
    }
    if (self.surface) |surface| surface.destroy();
    if (self.layer_surface) |layer_surface| layer_surface.destroy();
    if (self.frame_callback) |frame_callback| frame_callback.destroy();
}

pub fn outputChanged(self: *Output) !void {
    const wayland_context = self.wayland_context;

    if (self.surface == null) {
        assert(self.layer_surface == null);

        const compositor = wayland_context.compositor orelse return error.NoCompositor;
        const layer_shell = wayland_context.layer_shell orelse return error.NoLayerShell;

        const surface = try compositor.createSurface();
        self.surface = surface;

        Wayland.setSurfaceTransparent(compositor, surface);

        const layer_surface = try layer_shell.getLayerSurface(
            surface,
            self.output_context.output,
            .top,
            Wayland.NAMESPACE,
        );
        self.layer_surface = layer_surface;

        layer_surface.setSize(0, Config.getHeight());
        if (Config.isBottom()) {
            layer_surface.setAnchor(.{ .bottom = true, .left = true, .right = true });
        } else {
            layer_surface.setAnchor(.{ .top = true, .left = true, .right = true });
        }
        layer_surface.setExclusiveZone(Config.getHeight());
        layer_surface.setKeyboardInteractivity(.none);
        layer_surface.setListener(*Wayland, layerSurfaceListener, wayland_context);

        surface.commit();
    }
}

pub fn layerSurfaceConfigure(self: *Output) !void {
    const wayland_context = self.wayland_context;

    assert(wayland_context.compositor != null);
    assert(wayland_context.layer_shell != null);
    assert(self.surface != null);
    assert(self.layer_surface != null);

    if (self.window_size.x < MINIMUM_WIDTH or self.window_size.y < MINIMUM_HEIGHT) {
        log.info("Output '{s}' too small: {}x{}", .{
            self.outputName(),
            self.window_size.x,
            self.window_size.y,
        });
        if (self.frame_callback) |fc| fc.destroy();
        self.frame_callback = null;
        return;
    }

    self.scale = self.pending_scale;

    if (self.surface) |surface| {
        surface.setBufferScale(@intCast(self.scale));
    }

    log.info("Output '{s}' configured: {}x{} @ scale {}", .{
        self.outputName(),
        self.window_size.x,
        self.window_size.y,
        self.scale,
    });

    self.full_redraw = true;

    const area = self.currentArea();
    self.ensureRootContainer(area);

    self.ensureRenderer() catch {};

    self.draw();

    if (self.frame_callback) |fc| fc.destroy();
    self.frame_callback = self.surface.?.frame() catch @panic("Failed to get frame callback");
    self.frame_callback.?.setListener(*Wayland, nextFrame, wayland_context);
    self.surface.?.commit();
}

fn currentArea(self: *const Output) Rect {
    return .{
        .x = 0,
        .y = 0,
        .width = @intCast(self.window_size.x),
        .height = @intCast(self.window_size.y),
    };
}

fn outputName(self: *const Output) []const u8 {
    return self.output_context.name_buf[0..self.output_context.name_len];
}

fn initRootContainer(self: *Output, area: Rect) void {
    const output_name = self.outputName();
    self.root_container = RootContainer.init(
        std.heap.page_allocator,
        area,
        self.output_context.output,
        output_name,
        self.wayland_context,
        @import("config.zig").default_font_path,
    );
}

fn ensureRootContainer(self: *Output, area: Rect) void {
    if (self.root_container) |*rc| {
        rc.setArea(area);
    } else {
        self.initRootContainer(area);
    }
}

fn ensureRenderer(self: *Output) !void {
    const wl_shm = self.wayland_context.shm orelse return;
    if (self.renderer) |renderer| {
        try renderer.resize(@intCast(self.window_size.x), @intCast(self.window_size.y), self.scale);
    } else {
        self.renderer = try rdr.Renderer.init(
            std.heap.page_allocator,
            wl_shm,
            @intCast(self.window_size.x),
            @intCast(self.window_size.y),
            self.scale,
        );
    }
}

pub fn draw(self: *Output) void {
    const renderer = self.renderer orelse {
        log.warn("No renderer available", .{});
        return;
    };

    var acquired = renderer.acquire() orelse {
        log.warn("No buffers available", .{});
        return;
    };

    var surface = acquired.surface;
    const clip = Rect{ .x = 0, .y = 0, .width = @intCast(self.window_size.x), .height = @intCast(self.window_size.y) };

    // Draw background
    surface.clear(bgColor());

    if (self.root_container) |*rc| {
        self.damage_tracker.markFullDamage();
        rc.drawFrame(&surface, clip);
    }

    self.full_redraw = false;

    acquired.submit(self.surface.?, &self.damage_tracker);
    self.damage_tracker.commitFrame();
}

fn bgColor() Color {
    return Color.init(0x1e, 0x1e, 0x2e, 0xff);
}

pub fn getScale(self: *const Output) u31 {
    return self.scale;
}

pub fn requestFrame(self: *Output) void {
    if (self.frame_callback != null) return;
    if (self.surface == null) return;

    self.frame_callback = self.surface.?.frame() catch return;
    self.frame_callback.?.setListener(*Wayland, nextFrame, self.wayland_context);
    self.surface.?.commit();
}

pub fn getPopupSurface(self: *Output) ?*LayerPopup {
    if (self.popup) |*p| return p;
    return null;
}

pub fn showMenuPopup(
    self: *Output,
    center_x: geo.SizeSigned,
    width: Size,
    height: Size,
    draw_fn: LayerPopup.DrawFn,
    draw_ctx: ?*anyopaque,
) void {
    if (self.popup) |*p| {
        const screen_width: Size = @intCast(self.window_size.x);
        p.showCentered(.menu, center_x, 0, width, height, screen_width, self.scale, draw_fn, draw_ctx) catch |err| {
            log.warn("Failed to show menu popup: {s}", .{@errorName(err)});
        };
    }
}

pub fn showTooltipPopup(
    self: *Output,
    center_x: geo.SizeSigned,
    width: Size,
    height: Size,
    draw_fn: LayerPopup.DrawFn,
    draw_ctx: ?*anyopaque,
) void {
    if (self.popup) |*p| {
        const screen_width: Size = @intCast(self.window_size.x);
        p.showCentered(.tooltip, center_x, 0, width, height, screen_width, self.scale, draw_fn, draw_ctx) catch |err| {
            log.warn("Failed to show tooltip popup: {s}", .{@errorName(err)});
        };
    }
}

pub fn hidePopup(self: *Output) void {
    if (self.popup) |*p| {
        p.hide();
    }
}

pub fn isPopupVisible(self: *const Output) bool {
    if (self.popup) |p| {
        return p.isVisible();
    }
    return false;
}

pub fn getPopupBounds(self: *const Output) Rect {
    if (self.popup) |p| {
        return p.getBounds();
    }
    return Rect.zero;
}

pub fn reinitializeWidgets(self: *Output, old_container: *RootContainer) void {
    const new_height = Config.getHeight();

    self.hidePopup();

    old_container.deinit();
    self.root_container = null;

    if (self.layer_surface) |layer_surface| {
        layer_surface.setSize(0, new_height);
        if (Config.isBottom()) {
            layer_surface.setAnchor(.{ .bottom = true, .left = true, .right = true });
        } else {
            layer_surface.setAnchor(.{ .top = true, .left = true, .right = true });
        }
        layer_surface.setExclusiveZone(new_height);
    }

    if (self.popup) |*p| p.bar_at_bottom = Config.isBottom();

    const output_name = self.outputName();
    _ = output_name;
    self.full_redraw = true;
}

fn nextFrame(callback: *wl.Callback, event: wl.Callback.Event, wayland_context: *Wayland) void {
    switch (event) {
        .done => {},
    }

    const checker = struct {
        pub fn check(output: *const Output, target: *wl.Callback) bool {
            return output.frame_callback == target;
        }
    }.check;

    const output = wayland_context.findOutput(*wl.Callback, callback, &checker) orelse return;

    if (output.frame_callback) |fc| fc.destroy();
    output.frame_callback = null;

    var needs_redraw = output.full_redraw;
    if (!needs_redraw) {
        if (output.root_container) |*rc| {
            needs_redraw = rc.needsRedraw();
        }
    }

    if (needs_redraw) {
        output.draw();
    }

    // Always request next frame to keep the loop alive
    if (output.surface) |surface| {
        output.frame_callback = surface.frame() catch {
            output.frame_callback = null;
            return;
        };
        output.frame_callback.?.setListener(*Wayland, nextFrame, wayland_context);
        surface.commit();
    }
}

fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, wayland_context: *Wayland) void {
    const checker = struct {
        pub fn check(output: *const Output, target: *zwlr.LayerSurfaceV1) bool {
            return output.layer_surface == target;
        }
    }.check;

    const output = wayland_context.findOutput(*zwlr.LayerSurfaceV1, layer_surface, &checker) orelse return;

    switch (event) {
        .configure => |configure| {
            output.window_size.x = @intCast(configure.width);
            output.window_size.y = @intCast(configure.height);
            layer_surface.ackConfigure(configure.serial);
            output.layerSurfaceConfigure() catch {};
        },
        .closed => {
            output.layer_surface = null;
        },
    }
}

fn surfaceListener(surface: *wl.Surface, event: wl.Surface.Event, wayland_context: *Wayland) void {
    const checker = struct {
        pub fn check(output: *const Output, target: *wl.Surface) bool {
            return output.surface == target;
        }
    }.check;

    const output = wayland_context.findOutput(*wl.Surface, surface, &checker) orelse return;

    switch (event) {
        .preferred_buffer_scale => |scale_event| {
            const new_scale: u31 = @intCast(@max(1, scale_event.factor));
            if (new_scale != output.scale and new_scale != output.pending_scale) {
                output.pending_scale = new_scale;
                log.info("Output '{s}' received preferred_buffer_scale: {}", .{
                    output.outputName(),
                    new_scale,
                });
                output.full_redraw = true;
                output.requestFrame();
            }
        },
        .enter, .leave, .preferred_buffer_transform => {},
    }
}

fn applyPendingScaleChange(self: *Output) bool {
    if (self.pending_scale == self.scale) return false;
    if (self.renderer == null) return false;

    const new_scale = self.pending_scale;

    log.info("Applying scale change {} -> {} for output '{s}'", .{
        self.scale,
        new_scale,
        self.outputName(),
    });

    const renderer = self.renderer orelse return false;
    renderer.resize(
        @intCast(self.window_size.x),
        @intCast(self.window_size.y),
        new_scale,
    ) catch |err| {
        log.debug("Scale change deferred, buffers in use: {s}", .{@errorName(err)});
        return false;
    };

    self.scale = new_scale;
    self.full_redraw = true;
    return true;
}

fn outputListener(output: *wl.Output, event: wl.Output.Event, wayland_context: *Wayland) void {
    const checker = struct {
        pub fn check(o: *const Output, target: *wl.Output) bool {
            return o.output_context.output == target;
        }
    }.check;

    const output_info = wayland_context.findOutput(*wl.Output, output, checker) orelse return;
    var ctx = &output_info.output_context;

    switch (event) {
        .geometry => |geo_ev| {
            ctx.physical_height = @intCast(@max(0, geo_ev.physical_height));
            ctx.physical_width = @intCast(@max(0, geo_ev.physical_width));
            ctx.has_geometry = true;
            ctx.changed = true;
        },
        .mode => |mode| {
            ctx.screen_height = @intCast(@max(0, mode.height));
            ctx.screen_width = @intCast(@max(0, mode.width));
            ctx.refresh_mhz = @intCast(@max(0, mode.refresh));
            ctx.has_mode = true;
            ctx.changed = true;
        },
        .name => |name| {
            ctx.has_name = true;
            const name_str = std.mem.span(name.name);
            const copy_len = @min(name_str.len, ctx.name_buf.len);
            @memcpy(ctx.name_buf[0..copy_len], name_str[0..copy_len]);
            ctx.name_len = copy_len;
            ctx.changed = true;
        },
        .scale => |scale_ev| {
            const new_scale: u31 = @intCast(@max(1, scale_ev.factor));
            if (new_scale != output_info.scale) {
                output_info.pending_scale = new_scale;
                log.info("Output '{s}' received scale event: {}", .{
                    ctx.name_buf[0..ctx.name_len],
                    new_scale,
                });
            }
        },
        .description => {},
        .done => {
            if (ctx.has_geometry and ctx.has_name and ctx.has_mode and ctx.changed) {
                ctx.changed = false;
                output_info.outputChanged() catch {};
            }
        },
    }
}

pub const LayerPopup = @import("shell/popup.zig").LayerPopup;
