const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;

const Context = @import("wl.zig").Context;
const CursorShape = @import("wl.zig").CursorShape;

pub fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, ctx: *Context) void {
    switch (event) {
        .name => |name| {
            std.log.info("seat name: {s}", .{name.name});
        },
        .capabilities => |caps| {
            if (ctx.pointer) |p| { p.release(); ctx.pointer = null; }
            if (ctx.keyboard) |kb| { kb.release(); ctx.keyboard = null; }

            if (caps.capabilities.pointer) {
                const pointer = seat.getPointer() catch @panic("failed to get pointer");
                ctx.pointer = pointer;
                pointer.setListener(*Context, pointerListener, ctx);
            }
            if (caps.capabilities.keyboard) {
                const kb = seat.getKeyboard() catch @panic("failed to get keyboard");
                ctx.keyboard = kb;
                kb.setListener(*Context, keyboardListener, ctx);
            }
        },
    }
}

fn pointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, ctx: *Context) void {
    _ = pointer;
    switch (event) {
        .enter => |enter| {
            ctx.last_motion_output = .none;
            ctx.last_enter_serial = enter.serial;
            setCursorShape(ctx, enter.serial, .default);
        },
        .motion => |motion| {
            _ = motion;
        },
        .leave => {
            ctx.last_motion_output = .none;
            ctx.last_cursor_shape = null;
        },
        .button => {},
        .axis => {},
        .frame, .axis_stop, .axis_value120, .axis_discrete, .axis_source => {},
    }
}

fn keyboardListener(kb: *wl.Keyboard, event: wl.Keyboard.Event, ctx: *Context) void {
    _ = kb;
    _ = ctx;
    switch (event) {
        .key => {},
        .enter, .leave, .keymap, .modifiers, .repeat_info => {},
    }
}

fn setCursorShape(ctx: *Context, serial: u32, shape: CursorShape) void {
    if (ctx.cursor_shape_manager == null) return;
    if (ctx.last_cursor_shape == shape) return;
    ctx.last_cursor_shape = shape;
    if (ctx.pointer) |ptr| {
        const dev = ctx.cursor_shape_manager.?.getPointer(ptr) catch |err| {
            std.log.warn("cursor shape: {s}", .{@errorName(err)});
            return;
        };
        defer dev.destroy();
        dev.setShape(serial, shape);
    }
}
