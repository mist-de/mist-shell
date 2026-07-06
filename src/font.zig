const std = @import("std");
const c = @import("c.zig").c;

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

pub const Font = struct {
    allocator: std.mem.Allocator,
    ft_lib: c.FT_Library,
    ft_face: c.FT_Face,
    pixel_size: u32,
    hb_font: *c.hb_font_t,
    hb_buf: *c.hb_buffer_t,
    cache: std.AutoHashMapUnmanaged(u32, Glyph),

    pub fn init(allocator: std.mem.Allocator, path: []const u8, pixel_size: u32) !Font {
        var ft_lib: c.FT_Library = undefined;
        if (c.FT_Init_FreeType(&ft_lib) != 0) return error.FreeTypeInitFailed;

        var ft_face: c.FT_Face = undefined;
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        if (c.FT_New_Face(ft_lib, path_z, 0, &ft_face) != 0) {
            _ = c.FT_Done_FreeType(ft_lib);
            return error.FontNotFound;
        }

        if (c.FT_Set_Pixel_Sizes(ft_face, 0, pixel_size) != 0) {
            _ = c.FT_Done_Face(ft_face);
            _ = c.FT_Done_FreeType(ft_lib);
            return error.FontSizeInvalid;
        }

        const hb_font = c.hb_ft_font_create_referenced(ft_face).?;
        const hb_buf = c.hb_buffer_create().?;

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
        c.hb_buffer_destroy(f.hb_buf);
        c.hb_font_destroy(f.hb_font);
        _ = c.FT_Done_Face(f.ft_face);
        _ = c.FT_Done_FreeType(f.ft_lib);
    }

    pub fn getGlyph(f: *Font, codepoint: u32) !*const Glyph {
        const gop = try f.cache.getOrPut(f.allocator, codepoint);
        if (gop.found_existing) return gop.value_ptr;

        const glyph_index = c.FT_Get_Char_Index(f.ft_face, codepoint);
        if (glyph_index == 0) return error.GlyphNotFound;

        if (c.FT_Load_Glyph(f.ft_face, glyph_index, c.FT_LOAD_RENDER) != 0) {
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
