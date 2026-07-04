pub const packages = struct {
    pub const @"wayland-0.7.0-dev-lQa1kjT8AQDBstL61Gy3WCMtGwVaMN1p6w5wGfdDvP15" = struct {
        pub const build_root = "/home/ackerman/mist/zig-pkg/wayland-0.7.0-dev-lQa1kjT8AQDBstL61Gy3WCMtGwVaMN1p6w5wGfdDvP15";
        pub const build_zig = @import("wayland-0.7.0-dev-lQa1kjT8AQDBstL61Gy3WCMtGwVaMN1p6w5wGfdDvP15");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zig_wayland", "wayland-0.7.0-dev-lQa1kjT8AQDBstL61Gy3WCMtGwVaMN1p6w5wGfdDvP15" },
};
