# Mist — Featherlight Wayland Desktop Environment

A Wayland desktop environment built in Zig. Minimal, compositor-agnostic shell with
optional custom window manager for River.

**Status:** Rewriting from Rust (v0.2.0) to Zig (v1.0.0). Pre-alpha.

## Architecture

```
River Compositor (wlroots)      ← proven, 4K★, separate process
  ├── Mist Shell (Zig)          ← bar, launcher, notifications, OSD, lockscreen
  │   • FreeType + HarfBuzz     ← zero GLib, zero Cairo, same quality as Pango
  │   • wl_shm triple buffer    ← software-rendered, no GPU
  │   • basu D-Bus              ← sd-bus without systemd
  └── Mist WM (Zig)             ← custom river-window-management-v1 client
      • Tiling / Scrolling / DE (floating) modes
      • Hot-swappable modes     ← switch without restarting River
```

## Why Zig?

The Rust version hit 33 MB RSS from glib-rs (cairo-rs + pango-rs overhead).
Zig's @cImport calls FreeType+HarfBuzz C APIs directly — zero binding layer,
zero GLib, target 5-8 MB RSS.

## Quick Start

```bash
zig build -Doptimize=ReleaseSafe
# Run on River:
river -c zig-out/bin/mist-wm
```

## License

GPL-3.0-only
