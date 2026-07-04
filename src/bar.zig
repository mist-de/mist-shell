const std = @import("std");
const rdr = @import("shell/render.zig");
const Widget = @import("widget.zig").Widget;

pub const WidgetSlot = struct {
    widget: Widget,
    x: i32 = 0,
    w: u32 = 0,
};

pub const Section = struct {
    slots: [16]WidgetSlot = undefined,
    count: usize = 0,
    x: i32 = 0,
    w: u32 = 0,
};

pub const Bar = struct {
    width: u32,
    height: u32,
    padding: u32 = 8,
    bg_color: rdr.Color = .{ .r = 0x1e, .g = 0x1e, .b = 0x1e, .a = 0xff },
    sections: [3]Section = .{ .{}, .{}, .{} },
    section_names: [3][]const u8 = .{ "left", "center", "right" },

    pub fn init(width: u32, height: u32) Bar {
        return .{ .width = width, .height = height };
    }

    pub fn deinit(self: *Bar) void {
        for (&self.sections) |*s| {
            for (s.slots[0..s.count]) |*slot| slot.widget.deinit();
        }
    }

    pub fn addWidget(self: *Bar, section: usize, widget: Widget) !void {
        if (section >= 3) return error.InvalidSection;
        if (self.sections[section].count >= 16) return error.TooManyWidgets;
        self.sections[section].slots[self.sections[section].count] = .{ .widget = widget };
        self.sections[section].count += 1;
    }

    pub fn render(self: *Bar, surface: *rdr.Surface) void {
        surface.clear(self.bg_color);
        self.doLayout();
        for (&self.sections) |*s| {
            for (s.slots[0..s.count]) |*slot| {
                if (slot.w == 0) continue;
                slot.widget.render(surface, slot.x, 0, slot.w, self.height);
            }
        }
    }

    fn doLayout(self: *Bar) void {
        const inner_w = self.width -| 2 * self.padding;
        const section_w = inner_w / 3;

        // Layout left section: left-to-right
        var cx: i32 = @intCast(self.padding);
        for (self.sections[0].slots[0..self.sections[0].count]) |*slot| {
            slot.w = slot.widget.measure(self.width, self.height);
            slot.x = cx;
            cx += @as(i32, @intCast(slot.w));
        }
        self.sections[0].x = @intCast(self.padding);
        self.sections[0].w = @intCast(@max(0, cx - @as(i32, @intCast(self.padding))));

        // Layout center section: centered
        const center_start = @as(i32, @intCast(self.padding + section_w));
        var total_cw: u32 = 0;
        for (self.sections[1].slots[0..self.sections[1].count]) |*slot| {
            slot.w = slot.widget.measure(self.width, self.height);
            total_cw += slot.w;
        }
        cx = center_start + @as(i32, @intCast((section_w -| total_cw) / 2));
        for (self.sections[1].slots[0..self.sections[1].count]) |*slot| {
            slot.x = cx;
            cx += @as(i32, @intCast(slot.w));
        }
        self.sections[1].x = center_start;
        self.sections[1].w = section_w;

        // Layout right section: right-to-left
        const right_end = @as(i32, @intCast(self.width -| self.padding));
        cx = right_end;
        var i = self.sections[2].count;
        while (i > 0) {
            i -= 1;
            const slot = &self.sections[2].slots[i];
            slot.w = slot.widget.measure(self.width, self.height);
            cx -= @as(i32, @intCast(slot.w));
            slot.x = cx;
        }
        self.sections[2].x = @intCast(self.padding + 2 * section_w);
        self.sections[2].w = section_w;
    }
};
