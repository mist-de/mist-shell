pub const packages = struct {
    pub const @"wayland-0.5.0-lQa1knz8AQCh08NA8BeQrwJB9U3CfqcVAdHZYGRKIGuu" = struct {
        pub const build_root = "/home/ackerman/mist/zig-pkg/wayland-0.5.0-lQa1knz8AQCh08NA8BeQrwJB9U3CfqcVAdHZYGRKIGuu";
        pub const build_zig = @import("wayland-0.5.0-lQa1knz8AQCh08NA8BeQrwJB9U3CfqcVAdHZYGRKIGuu");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zig_wayland", "wayland-0.5.0-lQa1knz8AQCh08NA8BeQrwJB9U3CfqcVAdHZYGRKIGuu" },
};
