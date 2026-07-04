const std = @import("std");
const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftbitmap.h");
    @cInclude("harfbuzz/hb.h");
    @cInclude("harfbuzz/hb-ft.h");
});

const Color = @import("../render.zig").Color;

pub const Font = struct {
    lib: c.FT_Library,
    face: c.FT_Face,
    hb_font: ?*c.hb_font_t,
    size: f32,

    pub fn init(path: [:0]const u8, size: f32) !Font {
        var lib: c.FT_Library = undefined;
        if (c.FT_Init_FreeType(&lib) != 0) return error.InitFailed;
        errdefer _ = c.FT_Done_FreeType(lib);

        var face: c.FT_Face = undefined;
        if (c.FT_New_Face(lib, path.ptr, 0, &face) != 0) return error.FontNotFound;
        errdefer _ = c.FT_Done_Face(face);

        _ = c.FT_Set_Pixel_Sizes(face, 0, @intFromFloat(size));
        const hb_font = c.hb_ft_font_create(face, null);

        return .{ .lib = lib, .face = face, .hb_font = hb_font, .size = size };
    }

    pub fn deinit(self: *Font) void {
        if (self.hb_font) |f| c.hb_font_destroy(f);
        _ = c.FT_Done_Face(self.face);
        _ = c.FT_Done_FreeType(self.lib);
    }

    pub fn measureText(self: *Font, text: []const u8) u32 {
        const buf = c.hb_buffer_create() orelse return 0;
        defer c.hb_buffer_destroy(buf);
        c.hb_buffer_add_utf8(buf, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        c.hb_buffer_guess_segment_properties(buf);
        c.hb_shape(self.hb_font, buf, null, 0);
        const count = c.hb_buffer_get_length(buf);
        const pos = c.hb_buffer_get_glyph_positions(buf, null);
        var total: u32 = 0;
        for (pos[0..count]) |p| {
            total +%= @as(u32, @intCast(p.x_advance)) >> 6;
        }
        return total;
    }

    pub fn drawText(self: *Font, pixels: []Color, stride: u32, surf_w: u32, surf_h: u32, text: []const u8, x: i32, y: i32, color: Color) void {
        const buf = c.hb_buffer_create() orelse return;
        defer c.hb_buffer_destroy(buf);
        c.hb_buffer_add_utf8(buf, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        c.hb_buffer_guess_segment_properties(buf);
        c.hb_shape(self.hb_font, buf, null, 0);
        const count = c.hb_buffer_get_length(buf);
        const info = c.hb_buffer_get_glyph_infos(buf, null);
        const pos = c.hb_buffer_get_glyph_positions(buf, null);

        var cursor_x: i32 = x;
        for (info[0..count], pos[0..count]) |gi, gp| {
            const glyph_id = gi.codepoint;
            const advance = @as(i32, @intCast(gp.x_advance)) >> 6;
            const x_off = @as(i32, @intCast(gp.x_offset)) >> 6;
            const y_off = @as(i32, @intCast(gp.y_offset)) >> 6;

            if (c.FT_Load_Glyph(self.face, glyph_id, c.FT_LOAD_RENDER) != 0) {
                cursor_x +|= advance;
                continue;
            }
            const glyph = self.face.*.glyph;
            const bitmap = &glyph.*.bitmap;
            if (bitmap.*.buffer == null or bitmap.*.width == 0 or bitmap.*.rows == 0) {
                cursor_x +|= advance;
                continue;
            }

            const buf_src = bitmap.*.buffer[0 .. bitmap.*.width * bitmap.*.rows];
            const gx = cursor_x + x_off + glyph.*.bitmap_left;
            const gy = y - glyph.*.bitmap_top + y_off;
            blendGlyph(pixels, stride, surf_w, surf_h, buf_src, bitmap.*.width, bitmap.*.rows, gx, gy, color);

            cursor_x +|= advance;
        }
    }
};

fn blendGlyph(pixels: []Color, stride: u32, surf_w: u32, surf_h: u32, src: []const u8, w: u32, h: u32, x: i32, y: i32, color: Color) void {
    for (0..h) |row| {
        for (0..w) |col| {
            const alpha = src[row * w + col];
            if (alpha == 0) continue;
            const px = x + @as(i32, @intCast(col));
            const py = y + @as(i32, @intCast(row));
            if (px < 0 or py < 0) continue;
            const ux: u32 = @intCast(px);
            const uy: u32 = @intCast(py);
            if (ux >= surf_w or uy >= surf_h) continue;
            const idx = uy * stride + ux;

            const src_r = @as(u32, color.r);
            const src_g = @as(u32, color.g);
            const src_b = @as(u32, color.b);
            const src_a = @as(u32, alpha);
            const dst = pixels[idx];
            const inv_a = 255 - alpha;
            const out_r = (src_r * src_a + @as(u32, dst.r) * inv_a) / 255;
            const out_g = (src_g * src_a + @as(u32, dst.g) * inv_a) / 255;
            const out_b = (src_b * src_a + @as(u32, dst.b) * inv_a) / 255;
            const out_a = dst.a +| (src_a * (255 -| dst.a)) / 255;
            pixels[idx] = .{
                .r = @truncate(out_r),
                .g = @truncate(out_g),
                .b = @truncate(out_b),
                .a = @truncate(out_a),
            };
        }
    }
}
