const std = @import("std");
const Scanner = @import("wayland").Scanner;

fn pkgConfigVar(b: *std.Build, pkg_name: []const u8, variable: []const u8) ?[]const u8 {
    var code: u8 = undefined;
    const flag = std.fmt.allocPrint(b.allocator, "--variable={s}", .{variable}) catch return null;
    const stdout = b.runAllowFail(
        &.{ "pkg-config", flag, pkg_name },
        &code,
        .ignore,
    ) catch return null;
    return std.mem.trimEnd(u8, stdout, &[_]u8{ '\n', '\r', ' ' });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wayland_xml = blk: {
        const dir = pkgConfigVar(b, "wayland-scanner", "pkgdatadir") orelse
            @panic("wayland-scanner not found via pkg-config. Install wayland-scanner (wayland-devel on Fedora, libwayland-dev on Debian/Ubuntu, wayland on Arch/NixOS)");
        break :blk std.fs.path.join(b.allocator, &.{ dir, "wayland.xml" }) catch @panic("OOM");
    };
    const wayland_protocols = pkgConfigVar(b, "wayland-protocols", "pkgdatadir") orelse
        @panic("wayland-protocols not found via pkg-config. Install wayland-protocols on your distro");

    const scanner = Scanner.create(b, .{
        .wayland_xml = .{ .cwd_relative = wayland_xml },
        .wayland_protocols = .{ .cwd_relative = wayland_protocols },
    });

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    scanner.addCustomProtocol(b.path("protocols/wlr-layer-shell-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocols/wlr-foreign-toplevel-management-unstable-v1.xml"));
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");
    scanner.addSystemProtocol("staging/ext-workspace/ext-workspace-v1.xml");
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");

    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_seat", 8);
    scanner.generate("wl_output", 4);
    scanner.generate("zwlr_layer_shell_v1", 4);
    scanner.generate("zwlr_foreign_toplevel_manager_v1", 3);
    scanner.generate("ext_workspace_manager_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 1);
    scanner.generate("xdg_wm_base", 6);
    scanner.generate("zwp_tablet_manager_v2", 2);

    const exe = b.addExecutable(.{
        .name = "mist-bar",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wayland", .module = wayland },
            },
        }),
    });

    exe.root_module.link_libc = true;
    exe.root_module.addIncludePath(b.path("src"));
    exe.root_module.linkSystemLibrary("wayland-client", .{});
    exe.root_module.linkSystemLibrary("xkbcommon", .{});
    exe.root_module.linkSystemLibrary("freetype", .{});
    exe.root_module.linkSystemLibrary("harfbuzz", .{});

    const fonts_install = b.addInstallDirectory(.{
        .source_dir = b.path("fonts"),
        .install_dir = .prefix,
        .install_subdir = "fonts",
    });
    exe.step.dependOn(&fonts_install.step);

    b.installArtifact(exe);
}
