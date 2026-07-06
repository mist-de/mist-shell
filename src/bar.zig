const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const Context = @import("wl.zig").Context;
const LayerSurface = @import("wl.zig").LayerSurface;
const ShmBuffer = @import("wl.zig").ShmBuffer;
const Canvas = @import("render.zig").Canvas;
const config_mod = @import("config.zig");
const geometry = @import("geometry.zig");
const Color = @import("color.zig").Color;
const Rect = geometry.Rect;
const Font = @import("font.zig").Font;
const text_mod = @import("text.zig");

pub const Bar = struct {
    pub fn layerSurfaceListener(ls: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, bar: *Bar) void {
        switch (event) {
            .configure => |cfg| {
                ls.ackConfigure(cfg.serial);
                bar.layer.configured = true;
                bar.layer.width = @intCast(cfg.width);
                bar.layer.height = @intCast(cfg.height);
                bar.needs_full_redraw = true;
            },
            .closed => {},
        }
    }

    output_name: [64]u8,
    layer: LayerSurface = undefined,
    buffer: ?ShmBuffer = null,
    rect: Rect = .zero,
    font: ?Font = null,
    font_icon: ?Font = null,
    needs_full_redraw: bool = true,

    pub fn init(allocator: std.mem.Allocator, ctx: *Context, output_idx: usize, name: []const u8) !Bar {
        const output = &ctx.outputs[output_idx];
        const cfg = config_mod.get();
        const anchor: zwlr.LayerSurfaceV1.Anchor = if (cfg.bottom)
            .{ .bottom = true, .left = true, .right = true }
        else
            .{ .top = true, .left = true, .right = true };

        var bar = Bar{ .output_name = .{0} ** 64 };
        const name_len = @min(name.len, bar.output_name.len - 1);
        @memcpy(bar.output_name[0..name_len], name[0..name_len]);

        bar.layer = try LayerSurface.create(ctx, output, anchor, cfg.height);
        bar.rect = .{ .x = 0, .y = 0, .width = 0, .height = cfg.height };
        {
            if (config_mod.resolveFontPath(allocator, cfg.font_regular)) |fp| {
                defer allocator.free(fp);
                bar.font = Font.init(allocator, fp, cfg.font_size) catch null;
            } else |_| {}
            if (config_mod.resolveFontPath(allocator, cfg.font_icon)) |fp| {
                defer allocator.free(fp);
                bar.font_icon = Font.init(allocator, fp, cfg.font_size) catch null;
            } else |_| {}
        }

        return bar;
    }

    pub fn deinit(self: *Bar) void {
        if (self.buffer) |*b| b.deinit();
        if (self.font) |*f| f.deinit();
        if (self.font_icon) |*f| f.deinit();
        self.layer.destroy();
    }

    pub fn ensureBuffer(self: *Bar, ctx: *Context, width: i32) !void {
        if (self.buffer != null and self.buffer.?.width == width) return;
        if (self.buffer) |*b| b.deinit();
        const shm = ctx.shm orelse return;
        self.buffer = try ShmBuffer.create(shm, width, @intCast(self.rect.height));
        self.rect.width = @intCast(width);
        self.needs_full_redraw = true;
    }

    pub fn draw(self: *Bar, ctx: *Context) !void {
        if (!self.needs_full_redraw) return;
        const buf = self.buffer orelse return;
        var canvas = Canvas{
            .data = buf.data,
            .width = buf.width,
            .height = buf.height,
            .stride = buf.stride,
        };

        const bar_h: i32 = @intCast(self.rect.height);
        const bar_w: i32 = @intCast(self.rect.width);

        canvas.fill(Color.transparent);

        // ── End-4 M3 colors (exact from Appearance.qml) ──
        const col_layer1 = Color.rgba(0x1c, 0x1b, 0x1c, 0xE0);
        const col_on_layer0 = Color.rgba(0xe6, 0xe1, 0xe1, 0xFF);
        const col_on_layer1 = Color.rgba(0xcb, 0xc5, 0xca, 0xFF);
        const col_on_layer1_inactive = Color.rgba(0x7d, 0x78, 0x7c, 0xFF);
        const col_primary = Color.rgba(0xcb, 0xc4, 0xcb, 0xFF);
        const col_on_primary = Color.rgba(0x32, 0x2f, 0x34, 0xFF);
        const col_secondary_container = Color.rgba(0x4d, 0x4b, 0x4d, 0x99);
        const col_on_secondary_container = Color.rgba(0xec, 0xe6, 0xe9, 0xFF);
        const col_outline_variant = Color.rgba(0x49, 0x46, 0x4a, 0xFF);
        const col_outline = Color.rgba(0x94, 0x8f, 0x94, 0xFF);

        const bar_y: i32 = 0;
        const screen_rounding: i32 = 23;

        // ════════════════════════════════════════════════════════
        // LEFT SECTION: sidebar button + active window
        // ════════════════════════════════════════════════════════
        // LeftSidebarButton: RippleButton full radius (9999)
        // customIcon 19.5x19.5, buttonPadding 5 each side → 30px total
        // Layout.leftMargin = screenRounding
        const sidebar_x: i32 = screen_rounding;
        const sidebar_btn_w: i32 = 30;
        const sidebar_icon_cx = sidebar_x + @divTrunc(sidebar_btn_w, 2);
        const sidebar_icon_cy = @divTrunc(bar_h, 2);
        // Background is transparent (RippleButton default, only colLayer1Hover when hovered)
        // CustomIcon 19.5px (approx 10px radius), colOnLayer0
        canvas.fillCircle(sidebar_icon_cx, sidebar_icon_cy, 10, col_on_layer0);

        // ActiveWindow: Layout.leftMargin=10, Layout.rightMargin=screenRounding
        // App name (colSubtext = outline, 15px) + title (colOnLayer0, 17px), spacing=-4
        // Fills remaining width between left sidebar and center section
        const aw_x = sidebar_x + sidebar_btn_w + 10;
        const aw_right = @divTrunc(bar_w - screen_rounding, 2) - 80;
        if (aw_right > aw_x) {
            if (self.font) |*f| {
                const tbl = @divTrunc(bar_h - f.lineHeight(), 2) + f.baselineOffset();
                text_mod.renderText(&canvas, f, "Mist DE", aw_x, tbl, col_on_layer1);
            }
        }

        // ════════════════════════════════════════════════════════
        // CENTER SECTION: 3 BarGroups in a Row with spacing=4
        // ════════════════════════════════════════════════════════
        const center_spacing: i32 = 4;
        const center_mod_w: i32 = if (bar_w > 1200) 360 else if (bar_w > 1000) 280 else 190;
        const ws_btn_size: i32 = 26;
        const ws_count: i32 = 5;
        const ws_total = ws_btn_size * ws_count;
        const ws_bargroup_padding: i32 = 4;
        const ws_w = ws_total + ws_bargroup_padding * 2;
        const total_center = center_mod_w + center_spacing + ws_w + center_spacing + center_mod_w;
        const center_x = @divTrunc(bar_w - total_center, 2);

        // BarGroup: 4px vertical margin, 12px radius, colLayer1 bg
        const group_bg_y = bar_y + 4;
        const group_bg_h = bar_h - 8;
        const group_radius: i32 = 12;

        // ── LEFT CENTER GROUP: Resources + Media ──
        const lc_x = center_x;
        canvas.fillRoundedRect(lc_x, group_bg_y, center_mod_w, group_bg_h, group_radius, col_layer1);

        // Resources: 3 items in RowLayout
        // Resource internal: ClippedFilledCircularProgress 20px + 2px spacing + text
        // Resources wrapper: anchors.leftMargin=4, anchors.rightMargin=4
        // Between resources: Layout.leftMargin=6 when shown
        // Media: 20px ring + 4px spacing + song title
        var res_x = lc_x + 5;
        const res_y = @divTrunc(bar_h, 2);

        // Each resource: 20px ring (colOnSecondaryContainer) + text ("52" at small=15px)
        // ClippedFilledCircularProgress: implicitSize=20, lineWidth=2 (unsharpen)
        // arcRadius = 10 - 1 - 0.5 = 8.5, colPrimary = colOnSecondaryContainer
        // Background circle = transparentize(colPrimary, 0.5) = outline_variant
        // The ring is a PIE shape (filled from center), not a stroke
        // For simplicity: draw thick ring with fillRing
        for (0..3) |ri| {
            // Track: outline_variant ring (outer=10, inner=8)
            canvas.fillRing(res_x + 10, res_y, 8, 10, col_outline_variant);
            // Progress: colOnSecondaryContainer, full circle for now (placeholder)
            canvas.fillRing(res_x + 10, res_y, 8, 9, col_on_secondary_container);
            // Center icon dot (MaterialSymbol normal=16px, colOnSecondaryContainer)
            canvas.fillCircle(res_x + 10, res_y, 3, col_on_secondary_container);
            // Percentage text "52" (colOnLayer1, small=15px)
            if (self.font) |*f| {
                const tbl = @divTrunc(bar_h - f.lineHeight(), 2) + f.baselineOffset();
                text_mod.renderText(&canvas, f, "52", res_x + 22, tbl, col_on_layer1);
            }
            res_x += 42;
            if (ri < 2) res_x += 6;
        }

        // Media: circular progress (20px) + song title
        if (center_mod_w > 200) {
            res_x += 6;
            canvas.fillRing(res_x + 10, res_y, 8, 10, col_outline_variant);
            canvas.fillRing(res_x + 10, res_y, 8, 9, col_on_secondary_container);
            canvas.fillCircle(res_x + 10, res_y, 3, col_on_secondary_container);
            res_x += 24;
            const media_text_w = lc_x + center_mod_w - res_x - 5;
            if (media_text_w > 10) {
                if (self.font) |*f| {
                    const tbl = @divTrunc(bar_h - f.lineHeight(), 2) + f.baselineOffset();
                    text_mod.renderText(&canvas, f, "Song Title", res_x, tbl, col_on_layer1);
                }
            }
        }

        // ── MIDDLE CENTER GROUP: Workspaces ──
        const mc_x = lc_x + center_mod_w + center_spacing;
        canvas.fillRoundedRect(mc_x, group_bg_y, ws_w, group_bg_h, group_radius, col_layer1);

        const ws_cell_y = bar_y + @divTrunc(bar_h - ws_btn_size, 2);
        const ws_start_x = mc_x + ws_bargroup_padding;

        // Simulate: workspaces 0,1,2 occupied, workspace 0 active
        const occupied = [_]bool{ true, true, true, false, false };
        const active_ws: usize = 0;

        const half_btn = @divTrunc(ws_btn_size, 2);

        // ── Draw occupied backgrounds as grouped rounded rects (NO alpha overlap) ──
        var group_start: ?usize = null;
        for (0..6) |i| {
            const at_end = i == 5;
            if (!at_end and occupied[i]) {
                if (group_start == null) group_start = i;
            } else {
                if (group_start) |start| {
                    const end = i - 1;
                    const gx = ws_start_x + @as(i32, @intCast(start)) * ws_btn_size;
                    const gw = @as(i32, @intCast(end - start + 1)) * ws_btn_size;
                    if (start == end) {
                        canvas.fillCircle(gx + half_btn, ws_cell_y + half_btn, half_btn, col_secondary_container);
                    } else {
                        canvas.fillRoundedRect(gx, ws_cell_y, gw, ws_btn_size, half_btn, col_secondary_container);
                    }
                    group_start = null;
                }
            }
        }

        // ── Active workspace indicator ──
        // 22x22 pill (radius=full), colPrimary, 2px margin from button edge
        // Vertical+horizontal centered within the 26x26 button area
        const ws_active_margin: i32 = 2;
        const ws_active_size = ws_btn_size - ws_active_margin * 2;
        {
            const active_x = ws_start_x + @as(i32, @intCast(active_ws)) * ws_btn_size + ws_active_margin;
            const active_y = ws_cell_y + ws_active_margin;
            canvas.fillRoundedRect(active_x, active_y, ws_active_size, ws_active_size, 9999, col_primary);
        }

        // ── Workspace dots ──
        // width = workspaceButtonWidth * 0.18 = 26 * 0.18 = 4.68 ≈ 5px
        // Colors: active→colOnPrimary, occupied→colOnSecondaryContainer, empty→colOnLayer1Inactive
        const dot_diam: i32 = 5;
        const dot_r = @divTrunc(dot_diam, 2);
        for (0..5) |i| {
            const btn_x = ws_start_x + @as(i32, @intCast(i)) * ws_btn_size;
            const dot_cx = btn_x + half_btn;
            const dot_cy = ws_cell_y + half_btn;
            const dot_color = if (i == active_ws)
                col_on_primary
            else if (occupied[i])
                col_on_secondary_container
            else
                col_on_layer1_inactive;
            canvas.fillCircle(dot_cx, dot_cy, dot_r, dot_color);
        }

        // ── RIGHT CENTER GROUP: Clock + UtilButtons + Battery ──
        const rc_x = mc_x + ws_w + center_spacing;
        canvas.fillRoundedRect(rc_x, group_bg_y, center_mod_w, group_bg_h, group_radius, col_layer1);

        // BatteryIndicator: ClippedProgressBar, anchors.centerIn parent
        // valueBarWidth=30, valueBarHeight=18, colOnSecondaryContainer highlight
        // trackColor = transparentize(highlightColor, 0.5) = outline_variant
        // font pixelSize=13, shows percentage text
        const bat_w: i32 = 30;
        const bat_h: i32 = 18;
        // Right-aligned with 5px padding from right edge of group
        const bat_x = rc_x + center_mod_w - bat_w - 5;
        const bat_y_pos = @divTrunc(bar_h - bat_h, 2);
        // Track (background)
        canvas.fillRoundedRect(bat_x, bat_y_pos, bat_w, bat_h, 9999, col_outline_variant);
        // Fill (foreground, ~80%)
        const bat_pct: i32 = 80;
        const bat_fill_w = @divTrunc((bat_w - 4) * bat_pct, 100);
        canvas.fillRoundedRect(bat_x + 2, bat_y_pos + 2, bat_fill_w, bat_h - 4, 9999, col_on_secondary_container);
        // Percentage text "80" (13px, DemiBold for 2 chars)
        if (self.font) |*f| {
            const tbl = bat_y_pos + @divTrunc(bat_h - f.lineHeight(), 2) + f.baselineOffset();
            text_mod.renderText(&canvas, f, "80%", bat_x + 2, tbl, col_on_layer1);
        }

        // ClockWidget: RowLayout spacing=4, anchors.centerIn parent
        // Time (large=17px) + "•" (small=15px) + Date (small=15px)
        // All colOnLayer1
        const clock_x = rc_x + 5;
        if (self.font) |*f| {
            const tbl = @divTrunc(bar_h - f.lineHeight(), 2) + f.baselineOffset();
            var cx = clock_x;
            text_mod.renderText(&canvas, f, "12:34", cx, tbl, col_on_layer1);
            cx += text_mod.textWidth(f, "12:34") + 4;
            text_mod.renderText(&canvas, f, "•", cx, tbl, col_on_layer1);
            cx += text_mod.textWidth(f, "•") + 4;
            text_mod.renderText(&canvas, f, "Mon 6 Jul", cx, tbl, col_on_layer1);
        }

        // ════════════════════════════════════════════════════════
        // RIGHT SECTION: SysTray + indicator button
        // ════════════════════════════════════════════════════════
        // RowLayout layoutDirection=RightToLeft, spacing=5
        //   RippleButton (rightmost, Layout.rightMargin=screenRounding)
        //   SysTray (to the left)
        //   Item spacer (fills remaining)
        // RippleButton: indicatorsRowLayout, realSpacing=15
        //   6 icons at larger=19px: volume_off, mic_off, xkb, notification, network, bluetooth
        //   10px padding each side
        // SysTray: GridLayout columnSpacing=15
        //   RippleButton (overflow) 24x24
        //   3+ pinned items 24x24 each
        //   Separator "•"

        // Right sidebar button: 19px icons at 15px spacing + 10px padding each side
        const rsb_icon_size: i32 = 19;
        const rsb_spacing: i32 = 15;
        const rsb_icons_count: i32 = 6;
        const rsb_content_w = rsb_icons_count * rsb_icon_size + (rsb_icons_count - 1) * rsb_spacing;
        const rsb_w = rsb_content_w + 20;
        const rsb_x = bar_w - rsb_w - screen_rounding;

        // Background: transparent by default (transparentize(colLayer1Hover, 1) = transparent)
        // On hover: colLayer1Hover
        var icon_x = rsb_x + 10;
        const icon_cy = @divTrunc(bar_h, 2);
        for (0..6) |_| {
            canvas.fillRect(icon_x, icon_cy - @divTrunc(rsb_icon_size, 2), rsb_icon_size, rsb_icon_size, col_on_layer0);
            icon_x += rsb_icon_size + rsb_spacing;
        }

        // SysTray: pinned items + separator
        // GridLayout columnSpacing=15, each item 24x24
        // RowLayout between RippleButton and spacer, with spacing=5
        const tray_right = rsb_x - 5; // spacing between button and sys tray
        const tray_item_size: i32 = 24;
        // 4 items (overflow + 3 pinned), 3 gaps of 15px, 6px left margin
        const tray_items: i32 = 4;
        const tray_gaps = tray_items - 1;
        const tray_content_w = tray_items * tray_item_size + tray_gaps * 15;
        const tray_icons_x = tray_right - tray_content_w;
        var tix = tray_icons_x;
        for (0..tray_items) |_| {
            canvas.fillCircle(tix + @divTrunc(tray_item_size, 2), icon_cy, @divTrunc(tray_item_size, 2), col_outline);
            tix += tray_item_size + 15;
        }

        // ════════════════════════════════════════════════════════
        // Submit buffer
        // ════════════════════════════════════════════════════════
        self.layer.surface.attach(buf.buffer, 0, 0);
        self.layer.surface.damageBuffer(0, 0, @intCast(buf.width), @intCast(buf.height));
        self.layer.surface.commit();
        ctx.flush();

        self.needs_full_redraw = false;
    }
};
