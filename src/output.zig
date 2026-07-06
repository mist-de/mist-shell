const std = @import("std");
const Context = @import("wl.zig").Context;
const Bar = @import("bar.zig").Bar;
const config_mod = @import("config.zig");

pub const OutputState = struct {
    bar: ?Bar = null,
    output_idx: usize,
    name: [64]u8 = .{0} ** 64,
    configured: bool = false,
};

var outputs: [8]OutputState = undefined;
var output_count: usize = 0;

pub fn initOutput(ctx: *Context, output_idx: usize) !void {
    const name = std.mem.sliceTo(&ctx.outputs[output_idx].name, 0);
    if (output_count < 8) {
        outputs[output_count] = .{
            .output_idx = output_idx,
        };
        const name_len = @min(name.len, outputs[output_count].name.len - 1);
        @memcpy(outputs[output_count].name[0..name_len], name[0..name_len]);
        output_count += 1;
    }

    try ensureBar(ctx, output_idx);
}

pub fn ensureBar(ctx: *Context, output_idx: usize) !void {
    const name = std.mem.sliceTo(&ctx.outputs[output_idx].name, 0);
    for (0..output_count) |i| {
        const out = &outputs[i];
        if (out.output_idx != output_idx) continue;
        if (out.bar != null) return;

        const allocator = ctx.allocator;
        out.bar = try Bar.init(allocator, ctx, output_idx, name);
        std.log.info("ensureBar: bar created, setting listener...", .{});
        // Set per-bar layer surface listener with *Bar as data
        if (out.bar) |*bar| {
            if (bar.layer.layer_surface) |ls| {
                std.log.info("ensureBar: setting listener on {any}", .{ls});
                ls.setListener(*Bar, Bar.layerSurfaceListener, bar);
                std.log.info("ensureBar: listener set", .{});
            } else {
                std.log.warn("ensureBar: no layer_surface!", .{});
            }
        }
        break;
    }
}

pub fn drawOutputs(ctx: *Context) void {
    for (0..output_count) |i| {
        const out = &outputs[i];
        if (out.bar == null) continue;
        const output_info = &ctx.outputs[out.output_idx];

        const width = output_info.mode_w;
        if (width <= 0) continue;

        const bar = &out.bar.?;
        bar.ensureBuffer(ctx, width) catch |err| {
            std.log.warn("buffer: {s}", .{@errorName(err)});
            continue;
        };

        bar.draw(ctx) catch |err| {
            std.log.warn("draw: {s}", .{@errorName(err)});
        };
    }
}

pub fn deinit() void {
    for (0..output_count) |i| {
        if (outputs[i].bar) |*b| b.deinit();
    }
    output_count = 0;
}

pub fn markAllDirty(ctx: *Context) void {
    _ = ctx;
    for (0..output_count) |i| {
        if (outputs[i].bar) |*bar| {
            bar.needs_full_redraw = true;
        }
    }
}
