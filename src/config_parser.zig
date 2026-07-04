const std = @import("std");
const posix = std.posix;
const c = std.c;

const log = std.log.scoped(.ConfigParser);

pub const ConfigFile = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]const u8),
    owned: bool,

    pub fn init(allocator: std.mem.Allocator) ConfigFile {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([]const u8).init(allocator),
            .owned = true,
        };
    }

    pub fn deinit(self: *ConfigFile) void {
        if (self.owned) {
            var it = self.entries.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.entries.deinit();
        }
        self.* = undefined;
    }

    pub fn get(self: *const ConfigFile, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    pub fn getBool(self: *const ConfigFile, key: []const u8, default: bool) bool {
        const val = self.entries.get(key) orelse return default;
        return std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "yes") or std.mem.eql(u8, val, "1");
    }

    pub fn getInt(self: *const ConfigFile, key: []const u8, default: u16) u16 {
        const val = self.entries.get(key) orelse return default;
        return std.fmt.parseInt(u16, val, 10) catch default;
    }

    pub fn getColor(self: *const ConfigFile, key: []const u8, default: u32) u32 {
        const val = self.entries.get(key) orelse return default;
        if (val.len < 7 or val[0] != '#') return default;
        return std.fmt.parseInt(u32, val[1..], 16) catch default;
    }

    pub fn getString(self: *const ConfigFile, key: []const u8, default: []const u8) []const u8 {
        return self.entries.get(key) orelse default;
    }

    pub fn getWidgetList(self: *const ConfigFile, key: []const u8) WidgetList {
        const val = self.entries.get(key) orelse return WidgetList{};
        var result = WidgetList{};
        var iter = std.mem.splitScalar(u8, val, ',');
        while (iter.next()) |name| {
            const trimmed = std.mem.trim(u8, name, " \t");
            if (trimmed.len == 0) continue;
            const copy = self.allocator.dupe(u8, trimmed) catch continue;
            result.append(copy) catch self.allocator.free(copy);
        }
        return result;
    }
};

pub const WidgetList = struct {
    const max = 16;
    items: [max][]const u8 = undefined,
    len: usize = 0,

    pub fn append(self: *WidgetList, item: []const u8) !void {
        if (self.len >= max) return error.OutOfSpace;
        self.items[self.len] = item;
        self.len += 1;
    }

    pub fn slice(self: *const WidgetList) []const []const u8 {
        return self.items[0..self.len];
    }

    pub fn deinit(self: *WidgetList, allocator: std.mem.Allocator) void {
        for (self.items[0..self.len]) |s| allocator.free(s);
        self.len = 0;
    }
};

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const fd = c.open(path_z.ptr, @as(c.O, @bitCast(@as(u32, 0)))); // O_RDONLY
    if (fd < 0) return error.OpenFailed;
    defer _ = c.close(fd);

    const size = c.lseek(fd, 0, 2); // SEEK_END
    if (size < 0) return error.SeekFailed;
    _ = c.lseek(fd, 0, 0); // SEEK_SET

    const buf = try allocator.alloc(u8, @intCast(size));
    const n = c.read(fd, buf.ptr, @intCast(size));
    if (n < size) return error.ReadFailed;
    return buf;
}

pub fn parseConfigFile(allocator: std.mem.Allocator, path: []const u8) !ConfigFile {
    const contents = try readFile(allocator, path);
    defer allocator.free(contents);

    var result = ConfigFile.init(allocator);
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_pos], " \t");
        const value = std.mem.trim(u8, line[eq_pos + 1 ..], " \t\"'");
        if (key.len == 0) continue;
        const key_owned = try allocator.dupe(u8, key);
        const val_owned = try allocator.dupe(u8, value);
        try result.entries.put(key_owned, val_owned);
    }
    return result;
}

pub const Watcher = struct {
    fd: posix.fd_t,
    wd: c_int,
    watch_path: []const u8,
    buf: [4096]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Watcher {
        const fd = @as(posix.fd_t, @intCast(c.inotify_init1(0)));
        if (fd < 0) return error.InitFailed;
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        const wd = c.inotify_add_watch(fd, path_z.ptr, @as(u32, 0x8 | 0x100)); // IN_CLOSE_WRITE | IN_MOVED_TO
        if (wd < 0) return error.WatchFailed;
        const watch_copy = try allocator.dupe(u8, path);
        return .{ .fd = fd, .wd = wd, .watch_path = watch_copy };
    }

    pub fn deinit(self: *Watcher, allocator: std.mem.Allocator) void {
        _ = c.inotify_rm_watch(self.fd, self.wd);
        _ = c.close(self.fd);
        allocator.free(self.watch_path);
        self.* = undefined;
    }

    pub fn getFd(self: *const Watcher) posix.fd_t {
        return self.fd;
    }

    pub fn hasEvent(self: *Watcher) bool {
        const inotify_event = extern struct { wd: c_int, mask: u32, cookie: u32, len: u32 };
        const n = posix.read(self.fd, &self.buf, self.buf.len) catch return false;
        if (n < @sizeOf(inotify_event)) return false;
        return true;
    }
};

pub fn fileExists(path: []const u8) bool {
    const path_z = std.heap.page_allocator.dupeZ(u8, path) catch return false;
    defer std.heap.page_allocator.free(path_z);
    return c.access(path_z.ptr, 0) == 0;
}

pub fn findConfigPath(allocator: std.mem.Allocator, filename: []const u8) ?[]const u8 {
    const home_env = c.getenv("HOME") orelse return null;
    const home = std.mem.span(home_env);
    const user_path = std.fmt.allocPrint(allocator, "{s}/.config/mist-shell/{s}", .{ home, filename }) catch return null;
    if (fileExists(user_path)) return user_path;
    allocator.free(user_path);
    return null;
}

pub fn writeDefaultConfig(path: []const u8) !void {
    const defaults_str =
        \\# Mist bar configuration
        \\height = 38
        \\position = top
        \\font_path = /run/current-system/sw/share/X11/fonts/JetBrainsMonoNerdFont-Regular.ttf
        \\layout_left = button_menu, tags, active_window, mpris
        \\layout_center = clock
        \\layout_right = system_tray, sysinfo, network, volume, brightness, battery, power_profiles
        \\workspaces_count = 9
        \\clock_format = %H:%M
        \\
    ;
    // Create parent directory
    if (std.fs.path.dirname(path)) |dir| {
        const dir_z = std.heap.page_allocator.dupeZ(u8, dir) catch return;
        defer std.heap.page_allocator.free(dir_z);
        _ = c.mkdir(dir_z.ptr, @as(u32, 0o755));
    }
    const path_z = std.heap.page_allocator.dupeZ(u8, path) catch return;
    defer std.heap.page_allocator.free(path_z);
    const fd = c.open(path_z.ptr, @as(c.O, @bitCast(@as(u32, 0x41 | 0x200))), @as(c_int, 0o644)); // O_CREAT | O_WRONLY | O_TRUNC, mode 644
    if (fd < 0) return;
    defer _ = c.close(fd);
    _ = c.write(fd, defaults_str.ptr, defaults_str.len);
}
