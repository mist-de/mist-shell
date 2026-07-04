const std = @import("std");
const assert = std.debug.assert;

const Wayland = @import("wayland.zig");
const wl = Wayland.wl;

const Output = @import("output.zig");
const geo = @import("geo.zig");
const Point = geo.Point;

const log = std.log.scoped(.Seat);

pub const MouseButton = enum(u32) {
    left = 272,
    right = 273,
    middle = 274,
    side = 275,
    extra = 276,
    _,
};

pub const ButtonState = enum(u32) {
    released = 0,
    pressed = 1,
    _,
};

pub const Axis = wl.Pointer.Axis;

pub const CursorShape = Wayland.CursorShape;

pub fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, wayland_context: *Wayland) void {
    switch (event) {
        .name => |name| {
            log.debug("Seat name: {s}", .{name.name});
        },
        .capabilities => |capabilities| {
            if (wayland_context.pointer) |pointer| pointer.release();
            wayland_context.pointer = null;

            if (capabilities.capabilities.pointer) {
                const pointer = seat.getPointer() catch @panic("Failed to get pointer");
                wayland_context.pointer = pointer;
                pointer.setListener(*Wayland, pointerListener, wayland_context);
            }
        },
    }
}

fn pointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, wayland_context: *Wayland) void {
    assert(wayland_context.pointer != null);
    assert(pointer == wayland_context.pointer.?);

    switch (event) {
        .enter => |enter| {
            if (enter.surface) |surface| {
                const hit = classifySurface(wayland_context, surface) orelse return;
                switch (hit.target) {
                    .bar => {
                        wayland_context.last_motion_surface = hit.output_index;
                        wayland_context.last_enter_serial = enter.serial;
                        wayland_context.pointer_over_popup = false;

                        const output = outputAt(wayland_context, hit.output_index);
                        if (output.root_container == null) return;
                        const root_container = &output.root_container.?;

                        const point = eventPoint(enter.surface_x.toInt(), enter.surface_y.toInt());

                        if (root_container.area.containsPoint(point)) {
                            root_container.motion(point);
                        }

                        const cursor_shape = root_container.getCursorShape();
                        setCursorShape(wayland_context, pointer, enter.serial, cursor_shape);
                    },
                    .popup => {
                        wayland_context.last_motion_surface = hit.output_index;
                        wayland_context.last_enter_serial = enter.serial;
                        wayland_context.pointer_over_popup = true;

                        const output = outputAt(wayland_context, hit.output_index);
                        var cursor_shape: CursorShape = .default;
                        if (output.popup) |*popup| {
                            popup.last_pointer_pos = eventPoint(enter.surface_x.toInt(), enter.surface_y.toInt());
                            if (output.root_container) |*rc| {
                                cursor_shape = rc.getPopupCursorShape(popup.last_pointer_pos);
                            }
                        }

                        setCursorShape(wayland_context, pointer, enter.serial, cursor_shape);
                    },
                }
            }
        },
        .motion => |motion| {
            if (wayland_context.last_motion_surface == .none) return;

            const output = outputAt(wayland_context, wayland_context.last_motion_surface);

            if (wayland_context.pointer_over_popup) {
                if (output.popup) |*popup| {
                    const point = eventPoint(motion.surface_x.toInt(), motion.surface_y.toInt());
                    popup.last_pointer_pos = point;

                    if (output.root_container) |*rc| {
                        rc.handlePopupMotion(point);
                        const cursor_shape = rc.getPopupCursorShape(point);
                        setCursorShape(wayland_context, pointer, wayland_context.last_enter_serial, cursor_shape);
                    }
                }
            } else {
                if (output.root_container == null) return;
                const root_container = &output.root_container.?;

                const point = eventPoint(motion.surface_x.toInt(), motion.surface_y.toInt());

                if (root_container.area.containsPoint(point)) {
                    root_container.motion(point);
                }

                const cursor_shape = root_container.getCursorShape();
                setCursorShape(wayland_context, pointer, wayland_context.last_enter_serial, cursor_shape);
            }
        },
        .leave => |leave| {
            if (leave.surface) |surface| {
                const hit = classifySurface(wayland_context, surface) orelse {
                    wayland_context.last_cursor_shape = null;
                    return;
                };
                const output = outputAt(wayland_context, hit.output_index);
                switch (hit.target) {
                    .bar => {
                        if (output.root_container != null) {
                            output.root_container.?.leave();
                        }
                    },
                    .popup => {
                        wayland_context.pointer_over_popup = false;
                    },
                }
            }
            wayland_context.last_cursor_shape = null;
        },
        .button => |button| {
            const mouse_button: MouseButton = @enumFromInt(button.button);

            if (wayland_context.last_motion_surface != .none) {
                const output = outputAt(wayland_context, wayland_context.last_motion_surface);

                if (wayland_context.pointer_over_popup) {
                    if (output.root_container) |*rc| {
                        if (output.popup) |*popup| {
                            if (button.state == .pressed) {
                                rc.handlePopupClick(popup.last_pointer_pos, mouse_button);
                            } else {
                                rc.handlePopupRelease(popup.last_pointer_pos, mouse_button);
                            }
                        }
                    }
                } else {
                    if (button.state != .pressed) return;
                    if (output.root_container != null) {
                        output.root_container.?.click(mouse_button);
                    }
                }
            }
        },
        .axis => |axis| {
            const axis_value: i32 = axis.value.toInt();
            if (axis_value == 0) return;

            if (wayland_context.last_motion_surface != .none) {
                const output = outputAt(wayland_context, wayland_context.last_motion_surface);
                if (output.root_container) |*rc| {
                    if (wayland_context.pointer_over_popup) {
                        if (output.popup) |*popup| {
                            rc.handlePopupScroll(popup.last_pointer_pos, axis.axis, axis_value);
                        }
                    } else {
                        rc.scroll(axis.axis, axis_value);
                    }
                }
            }
        },
        .frame, .axis_stop, .axis_discrete, .axis_source => {},
    }
}

const SurfaceTarget = enum { bar, popup };

const SurfaceHit = struct {
    output_index: Wayland.OutputIndex,
    target: SurfaceTarget,
};

fn classifySurface(wayland_context: *Wayland, surface: *wl.Surface) ?SurfaceHit {
    for (wayland_context.outputs[0..wayland_context.output_count], 0..) |*output, i| {
        const idx = Wayland.OutputIndex.fromInt(i);
        if (output.surface == surface) {
            return .{ .output_index = idx, .target = .bar };
        }
        if (output.popup) |*popup| {
            if (popup.surface == surface) {
                return .{ .output_index = idx, .target = .popup };
            }
        }
    }
    return null;
}

fn outputAt(wayland_context: *Wayland, output_index: Wayland.OutputIndex) *Output {
    return &wayland_context.outputs[@intFromEnum(output_index)];
}

fn eventPoint(x: i32, y: i32) Point {
    return .{
        .x = @max(x, 0),
        .y = @max(y, 0),
    };
}

fn setCursorShape(wayland_context: *Wayland, pointer: *wl.Pointer, serial: u32, shape: CursorShape) void {
    if (wayland_context.last_cursor_shape == shape) return;
    wayland_context.last_cursor_shape = shape;

    if (wayland_context.cursor_shape_manager) |cursor_shape_manager| {
        const pointer_device = cursor_shape_manager.getPointer(pointer) catch |err| {
            log.warn("Failed to get pointer device: {s}", .{@errorName(err)});
            return;
        };
        defer pointer_device.destroy();
        pointer_device.setShape(serial, shape);
    }
}
