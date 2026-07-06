const std = @import("std");
const cc = @import("c.zig").c;
const Color = @import("config.zig").Color;

// ═══════════════════════════════════════════════════════════
// Canvas — pixel drawing primitives
// ═══════════════════════════════════════════════════════════

pub const Canvas = struct {
    data: []align(std.heap.page_size_min) u8,
    width: i32,
    height: i32,
    stride: i32,

    fn blendPixel(dst_pixel: u32, src: Color) u32 {
        if (src.a == 0) return dst_pixel;
        if (src.a == 255) return src.toPixel();

        const sa = @as(u32, src.a);
        const sa_inv = 255 - sa;

        const da = @as(u32, (dst_pixel >> 24) & 0xFF);
        const dr = @as(u32, (dst_pixel >> 16) & 0xFF);
        const dg = @as(u32, (dst_pixel >> 8) & 0xFF);
        const db = @as(u32, dst_pixel & 0xFF);

        const out_a = sa + da * sa_inv / 255;
        if (out_a == 0) return 0;
        const out_r = @as(u32, src.r) * sa / 255 + dr * sa_inv / 255;
        const out_g = @as(u32, src.g) * sa / 255 + dg * sa_inv / 255;
        const out_b = @as(u32, src.b) * sa / 255 + db * sa_inv / 255;

        return (out_a << 24) | (out_r << 16) | (out_g << 8) | out_b;
    }

    fn coverageAA(dist: u32, r_u: u32, band: u32) u32 {
        if (dist <= r_u -| band) return 255;
        if (dist >= r_u + band) return 0;
        const delta = dist - (r_u -| band);
        const t = @as(f32, @floatFromInt(delta)) / @as(f32, @floatFromInt(band * 2));
        const smooth = t * t * (3.0 - 2.0 * t);
        return @intFromFloat((1.0 - smooth) * 255.0);
    }

    pub fn fillRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        const x0 = @max(0, x);
        const y0 = @max(0, y);
        const x1 = @min(self.width, x + w);
        const y1 = @min(self.height, y + h);
        if (x0 >= x1 or y0 >= y1) return;

        if (color.a == 255) {
            const p = color.toPixel();
            var row: i32 = y0;
            while (row < y1) : (row += 1) {
                const offset = @as(usize, @intCast(row * self.stride + x0 * 4));
                const pixels = @as([*]u32, @ptrCast(@alignCast(&self.data[offset])))[0..@intCast(x1 - x0)];
                @memset(pixels, p);
            }
        } else if (color.a == 0) {
            return;
        } else {
            var row: i32 = y0;
            while (row < y1) : (row += 1) {
                var col: i32 = x0;
                while (col < x1) : (col += 1) {
                    const offset = @as(usize, @intCast(row * self.stride + col * 4));
                    const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                    dst.* = blendPixel(dst.*, color);
                }
            }
        }
    }

    pub fn fillRoundedRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, radius: i32, color: Color) void {
        if (radius <= 0) {
            self.fillRect(x, y, w, h, color);
            return;
        }
        if (color.a == 0) return;

        const x0 = @max(0, x);
        const y0 = @max(0, y);
        const x1 = @min(self.width, x + w);
        const y1 = @min(self.height, y + h);
        if (x0 >= x1 or y0 >= y1) return;

        const r = @min(radius, @divTrunc(@min(w, h), 2));
        const r_u: u32 = @intCast(r);
        const r_sq = r_u * r_u;
        const band: u32 = @max(2, @divTrunc(r_u + 2, 3));

        var row: i32 = y0;
        while (row < y1) : (row += 1) {
            const py = row - y;
            const in_y_top = py < r;
            const in_y_bot = py >= h - r;

            var col: i32 = x0;
            while (col < x1) : (col += 1) {
                const px = col - x;
                const in_x_left = px < r;
                const in_x_right = px >= w - r;

                if ((!in_y_top and !in_y_bot) or (!in_x_left and !in_x_right)) {
                    const offset = @as(usize, @intCast(row * self.stride + col * 4));
                    const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                    dst.* = blendPixel(dst.*, color);
                    continue;
                }

                const cx: i32 = if (in_x_left) r else w - r - 1;
                const cy: i32 = if (in_y_top) r else h - r - 1;
                const dx = @as(i32, px) - cx;
                const dy = @as(i32, py) - cy;
                const dist_sq: u32 = @intCast(dx * dx + dy * dy);

                if (dist_sq >= r_sq + band * band) continue;
                if (dist_sq <= r_sq -| band *| band) {
                    const offset = @as(usize, @intCast(row * self.stride + col * 4));
                    const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                    dst.* = blendPixel(dst.*, color);
                    continue;
                }

                const dist = isqrt(dist_sq);
                const coverage = coverageAA(dist, r_u, band);
                if (coverage == 0) continue;

                const c = Color{
                    .r = color.r,
                    .g = color.g,
                    .b = color.b,
                    .a = @intCast(@min(@as(u32, 255), @as(u32, color.a) * coverage / 255)),
                };
                const offset = @as(usize, @intCast(row * self.stride + col * 4));
                const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                dst.* = blendPixel(dst.*, c);
            }
        }
    }

    pub fn fillCircle(self: *Canvas, cx: i32, cy: i32, radius: i32, color: Color) void {
        if (radius <= 0 or color.a == 0) return;
        const x0 = @max(0, cx - radius - 1);
        const y0 = @max(0, cy - radius - 1);
        const x1 = @min(self.width, cx + radius + 2);
        const y1 = @min(self.height, cy + radius + 2);

        const r_u: u32 = @intCast(radius);
        const r_sq = r_u * r_u;
        const band: u32 = if (r_u < 4) 1 else @max(2, @divTrunc(r_u + 2, 3));

        var row: i32 = y0;
        while (row < y1) : (row += 1) {
            var col: i32 = x0;
            while (col < x1) : (col += 1) {
                const dx = @as(i32, col) - cx;
                const dy = @as(i32, row) - cy;
                const dist_sq: u32 = @intCast(dx * dx + dy * dy);

                if (dist_sq >= r_sq + band * band) continue;
                if (dist_sq <= r_sq -| band *| band) {
                    const offset = @as(usize, @intCast(row * self.stride + col * 4));
                    const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                    dst.* = blendPixel(dst.*, color);
                    continue;
                }

                const dist = isqrt(dist_sq);
                const coverage = coverageAA(dist, r_u, band);
                if (coverage == 0) continue;

                const c = Color{
                    .r = color.r,
                    .g = color.g,
                    .b = color.b,
                    .a = @intCast(@min(@as(u32, 255), @as(u32, color.a) * coverage / 255)),
                };
                const offset = @as(usize, @intCast(row * self.stride + col * 4));
                const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                dst.* = blendPixel(dst.*, c);
            }
        }
    }

    pub fn fillRing(self: *Canvas, cx: i32, cy: i32, inner_r: i32, outer_r: i32, color: Color) void {
        if (outer_r <= inner_r or color.a == 0) return;
        const x0 = @max(0, cx - outer_r - 1);
        const y0 = @max(0, cy - outer_r - 1);
        const x1 = @min(self.width, cx + outer_r + 2);
        const y1 = @min(self.height, cy + outer_r + 2);

        const outer_u: u32 = @intCast(outer_r);
        const inner_u: u32 = @intCast(inner_r);
        const outer_sq = outer_u * outer_u;
        const inner_sq = inner_u * inner_u;
        const band: u32 = if (outer_u < 4) 1 else @max(2, @divTrunc(outer_u + 2, 3));

        var row: i32 = y0;
        while (row < y1) : (row += 1) {
            var col: i32 = x0;
            while (col < x1) : (col += 1) {
                const dx = @as(i32, col) - cx;
                const dy = @as(i32, row) - cy;
                const dist_sq: u32 = @intCast(dx * dx + dy * dy);

                if (dist_sq >= outer_sq + band * band) continue;
                if (dist_sq <= inner_sq -| band *| band) continue;

                const dist = isqrt(dist_sq);
                var cov_outer: u32 = 255;
                if (dist >= outer_u -| band) {
                    cov_outer = coverageAA(dist, outer_u, band);
                }
                var cov_inner: u32 = 0;
                if (dist >= inner_u -| band and inner_r > 0) {
                    cov_inner = coverageAA(dist, inner_u, band);
                }
                const coverage = cov_outer -| cov_inner;
                if (coverage == 0) continue;

                const c = Color{
                    .r = color.r,
                    .g = color.g,
                    .b = color.b,
                    .a = @intCast(@min(@as(u32, 255), @as(u32, color.a) * coverage / 255)),
                };
                const offset = @as(usize, @intCast(row * self.stride + col * 4));
                const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                dst.* = blendPixel(dst.*, c);
            }
        }
    }

    pub fn blitGray(self: *Canvas, x: i32, y: i32, w: u32, h: u32, pitch: i32, buf: []const u8, color: Color) void {
        if (color.a == 0 or w == 0 or h == 0) return;
        const x0 = @max(0, x);
        const y0 = @max(0, y);
        const x1 = @min(self.width, x + @as(i32, @intCast(w)));
        const y1 = @min(self.height, y + @as(i32, @intCast(h)));
        if (x0 >= x1 or y0 >= y1) return;

        var row: i32 = y0;
        while (row < y1) : (row += 1) {
            const src_row = @as(usize, @intCast((row - y) * pitch));
            var col: i32 = x0;
            while (col < x1) : (col += 1) {
                const src_col = @as(usize, @intCast(col - x));
                const cov = buf[src_row + src_col];
                if (cov == 0) continue;
                const alpha: u32 = @as(u32, color.a) * cov / 255;
                if (alpha == 0) continue;
                const offset = @as(usize, @intCast(row * self.stride + col * 4));
                const dst = @as(*align(1) u32, @ptrCast(&self.data[offset]));
                const dst_val = dst.*;

                const sa = alpha;
                const sa_inv = 255 - sa;
                const da = (dst_val >> 24) & 0xFF;
                const dr = (dst_val >> 16) & 0xFF;
                const dg = (dst_val >> 8) & 0xFF;
                const db = dst_val & 0xFF;

                const out_a = sa + da * sa_inv / 255;
                if (out_a == 0) {
                    dst.* = 0;
                    continue;
                }
                const out_r = @as(u32, color.r) * sa / 255 + dr * sa_inv / 255;
                const out_g = @as(u32, color.g) * sa / 255 + dg * sa_inv / 255;
                const out_b = @as(u32, color.b) * sa / 255 + db * sa_inv / 255;

                dst.* = (out_a << 24) | (out_r << 16) | (out_g << 8) | out_b;
            }
        }
    }

    pub fn fill(self: *Canvas, color: Color) void {
        self.fillRect(0, 0, self.width, self.height, color);
    }

    fn isqrt(n: u32) u32 {
        if (n == 0) return 0;
        var x = n;
        var y = (x + 1) / 2;
        while (y < x) {
            x = y;
            y = (x + n / x) / 2;
        }
        return x;
    }
};

// ═══════════════════════════════════════════════════════════
// Glyph cache entry
// ═══════════════════════════════════════════════════════════

pub const Glyph = struct {
    width: u32,
    height: u32,
    pitch: i32,
    left: i32,
    top: i32,
    advance_x: i32,
    buf: []u8,

    pub fn deinit(g: *Glyph, allocator: std.mem.Allocator) void {
        allocator.free(g.buf);
    }
};

// ═══════════════════════════════════════════════════════════
// Font (FreeType + HarfBuzz)
// ═══════════════════════════════════════════════════════════

pub const Font = struct {
    allocator: std.mem.Allocator,
    ft_lib: cc.FT_Library,
    ft_face: cc.FT_Face,
    pixel_size: u32,
    hb_font: *cc.hb_font_t,
    hb_buf: *cc.hb_buffer_t,
    cache: std.AutoHashMapUnmanaged(u32, Glyph),

    pub fn init(allocator: std.mem.Allocator, path: []const u8, pixel_size: u32) !Font {
        var ft_lib: cc.FT_Library = undefined;
        if (cc.FT_Init_FreeType(&ft_lib) != 0) return error.FreeTypeInitFailed;

        var ft_face: cc.FT_Face = undefined;
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        if (cc.FT_New_Face(ft_lib, path_z, 0, &ft_face) != 0) {
            _ = cc.FT_Done_FreeType(ft_lib);
            return error.FontNotFound;
        }

        if (cc.FT_Set_Pixel_Sizes(ft_face, 0, pixel_size) != 0) {
            _ = cc.FT_Done_Face(ft_face);
            _ = cc.FT_Done_FreeType(ft_lib);
            return error.FontSizeInvalid;
        }

        const hb_font = cc.hb_ft_font_create_referenced(ft_face).?;
        const hb_buf = cc.hb_buffer_create().?;

        return Font{
            .allocator = allocator,
            .ft_lib = ft_lib,
            .ft_face = ft_face,
            .pixel_size = pixel_size,
            .hb_font = hb_font,
            .hb_buf = hb_buf,
            .cache = .{},
        };
    }

    pub fn deinit(f: *Font) void {
        var iter = f.cache.iterator();
        while (iter.next()) |entry| {
            var g = &entry.value_ptr.*;
            g.deinit(f.allocator);
        }
        f.cache.deinit(f.allocator);
        cc.hb_buffer_destroy(f.hb_buf);
        cc.hb_font_destroy(f.hb_font);
        _ = cc.FT_Done_Face(f.ft_face);
        _ = cc.FT_Done_FreeType(f.ft_lib);
    }

    pub fn getGlyph(f: *Font, glyph_index: u32) !*const Glyph {
        const gop = try f.cache.getOrPut(f.allocator, glyph_index);
        if (gop.found_existing) return gop.value_ptr;

        if (cc.FT_Load_Glyph(f.ft_face, glyph_index, cc.FT_LOAD_RENDER) != 0) {
            return error.GlyphRenderFailed;
        }

        const slot = f.ft_face.*.glyph;
        const bitmap = slot.*.bitmap;
        const pitch = bitmap.pitch;
        const rows = bitmap.rows;
        const buf_len: usize = @intCast(@abs(pitch) * rows);
        const buf = try f.allocator.alloc(u8, buf_len);
        @memcpy(buf, bitmap.buffer[0..buf_len]);

        gop.value_ptr.* = Glyph{
            .width = @intCast(bitmap.width),
            .height = @intCast(rows),
            .pitch = pitch,
            .left = slot.*.bitmap_left,
            .top = slot.*.bitmap_top,
            .advance_x = @intCast(slot.*.metrics.horiAdvance >> 6),
            .buf = buf,
        };

        return gop.value_ptr;
    }

    pub fn baselineOffset(f: *const Font) i32 {
        const ascender: i32 = @intCast(f.ft_face.*.size.*.metrics.ascender >> 6);
        return ascender;
    }

    pub fn lineHeight(f: *const Font) i32 {
        const ascender: i32 = @intCast(f.ft_face.*.size.*.metrics.ascender >> 6);
        const descender: i32 = @intCast(f.ft_face.*.size.*.metrics.descender >> 6);
        return ascender - descender;
    }
};

// ═══════════════════════════════════════════════════════════
// Text shaping + rendering (HarfBuzz)
// ═══════════════════════════════════════════════════════════

fn shape(font: *Font, text: []const u8, count: *c_uint) struct { [*c]cc.hb_glyph_info_t, [*c]cc.hb_glyph_position_t } {
    cc.hb_buffer_reset(font.hb_buf);
    if (text.len > 0) {
        cc.hb_buffer_add_utf8(font.hb_buf, text.ptr, @intCast(text.len), 0, @intCast(text.len));
    }
    cc.hb_buffer_set_direction(font.hb_buf, cc.HB_DIRECTION_LTR);
    cc.hb_buffer_set_script(font.hb_buf, cc.HB_SCRIPT_LATIN);
    cc.hb_buffer_set_language(font.hb_buf, cc.hb_language_from_string("en", 2));
    cc.hb_shape(font.hb_font, font.hb_buf, null, 0);
    const info = cc.hb_buffer_get_glyph_infos(font.hb_buf, count);
    const pos = cc.hb_buffer_get_glyph_positions(font.hb_buf, count);
    return .{ info, pos };
}

pub fn renderText(canvas: *Canvas, font: *Font, text: []const u8, x: i32, y: i32, color: Color) void {
    if (color.a == 0 or text.len == 0) return;

    var glyph_count: c_uint = 0;
    const info, const pos = shape(font, text, &glyph_count);
    if (glyph_count == 0) return;

    var pen_x: i32 = x;
    const baseline_y: i32 = y;

    var i: u32 = 0;
    while (i < glyph_count) : (i += 1) {
        const gi = info[i];
        const gp = pos[i];
        const x_offset: i32 = @intCast(gp.x_offset >> 6);
        const y_offset: i32 = @intCast(gp.y_offset >> 6);
        const x_advance: i32 = @intCast(gp.x_advance >> 6);
        const glyph = font.getGlyph(gi.codepoint) catch {
            pen_x += x_advance;
            continue;
        };

        const dst_x = pen_x + x_offset + glyph.left;
        const dst_y = baseline_y + y_offset - glyph.top;

        canvas.blitGray(dst_x, dst_y, @intCast(glyph.width), @intCast(glyph.height), glyph.pitch, glyph.buf, color);

        pen_x += x_advance;
    }
}

pub fn textWidth(font: *Font, text: []const u8) i32 {
    if (text.len == 0) return 0;

    var glyph_count: c_uint = 0;
    const info_discard, const pos = shape(font, text, &glyph_count);
    _ = info_discard;
    if (glyph_count == 0) return 0;

    var total: i32 = 0;
    var i: u32 = 0;
    while (i < glyph_count) : (i += 1) {
        total += @as(i32, @intCast(pos[i].x_advance >> 6));
    }
    return total;
}
