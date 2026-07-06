# Mist

> [!WARNING]
> **This project is in early development and is not yet stable.**
> Expect broken rendering, missing features, and frequent breaking changes.
> Do not use this as your daily shell yet.

A minimal Wayland desktop environment shell written in Zig.

Inspired by [end-4](https://github.com/end-4/dots-hyprland), but rewritten from scratch with zero GPU dependencies — pure software rendering via wl_shm.

## Quick Start

```sh
# Clone
git clone https://github.com/ackerman/mist.git
cd mist

# Build (requires nix-shell on NixOS, or see deps below)
nix-shell --run "zig build -Doptimize=ReleaseFast -- -lwayland-client -lxkbcommon -lfreetype -lharfbuzz"

# Run (from a Wayland compositor like river)
./zig-out/bin/mist-bar
```

<details>
<summary>Dependencies by distro</summary>

**Debian / Ubuntu:**
```sh
sudo apt install libwayland-dev wayland-protocols libxkbcommon-dev \
  libfreetype-dev libharfbuzz-dev pkg-config
```

**Fedora:**
```sh
sudo dnf install wayland-devel wayland-protocols-devel libxkbcommon-devel \
  freetype-devel harfbuzz-devel pkg-config
```

**Arch Linux:**
```sh
sudo pacman -S wayland wayland-protocols libxkbcommon freetype2 harfbuzz pkgconf
```

**Void Linux:**
```sh
sudo xbps-install -S wayland-devel wayland-protocols libxkbcommon-devel \
  freetype-devel harfbuzz-devel pkg-config
```

**openSUSE:**
```sh
sudo zypper install wayland-devel wayland-protocols-devel libxkbcommon-devel \
  freetype2-devel harfbuzz-devel pkg-config
```

**NixOS:**
```sh
# Packages already in configuration.nix
# Use nix-shell for development:
nix-shell
```

</details>

<details>
<summary>Build from source (without nix-shell)</summary>

```sh
# Ensure pkg-config can find all libraries
zig build -Doptimize=ReleaseFast -- -lwayland-client -lxkbcommon -lfreetype -lharfbuzz

# Binary is at zig-out/bin/mist-bar
# Fonts are installed to zig-out/fonts/
```

</details>

## Status

> [!CAUTION]
> The bar is **unstable**. Expect visual glitches, pixel artifacts, and incomplete widgets.

| Component | Status |
|-----------|--------|
| Wayland layer shell rendering | Working (wl_shm, software-only) |
| Smoothstep AA (circles, rects, rings) | Working |
| FreeType + HarfBuzz text rendering | Working (basic) |
| M3 color palette | Working |
| Workspace indicators | Working (static, no live updates) |
| Resource rings | Working (placeholder data) |
| Clock, battery, media | Working (placeholder data) |
| Input dispatch (click, scroll) | Not implemented |
| D-Bus services | Not implemented |
| Auto-hide | Not implemented |
| Popups / tooltips | Not implemented |
| Config file parsing | Not implemented |
| Per-output lifecycle | Partial |

**Known issues:**
- Pixel artifacts on bar edges
- Font rendering may break at certain sizes
- No live workspace updates from compositor
- No input handling — bar is display-only

## Design Principles

- **Zero GPU** — pure wl_shm software rendering
- **Zero GLib** — no GTK, no GLib, no GNOME dependencies
- **Zero hardcoded paths** — all libraries discovered via pkg-config
- **Portable** — works on any Linux distro with the required packages
- **Minimal** — target 1-2 MB stripped binary

## Fonts

Bundled in `fonts/`:
- Inter Regular/Bold — UI text
- NotoSans Nerd Font — icons
- JetBrains Mono Nerd Font — monospace icons
- Material Symbols Rounded — material icons

<details>
<summary>Architecture</summary>

```
mist/
├── src/
│   ├── main.zig          Entry point, event loop
│   ├── wl.zig            Wayland context, layer surfaces, SHM buffers
│   ├── bar.zig           Bar layout, widget rendering
│   ├── render.zig        Pixel-level canvas with smoothstep AA
│   ├── font.zig          FreeType glyph rendering, cache
│   ├── text.zig          HarfBuzz text shaping, compositing
│   ├── config.zig        Configuration, colors, font paths
│   ├── seat.zig          Input event handling (stubs)
│   ├── output.zig        Output lifecycle, bar per-monitor
│   ├── geometry.zig      Point, Rect, Size types
│   ├── color.zig         ARGB color, premultiplied alpha
│   ├── util.zig          BoundedArray generic
│   ├── c.zig             @cImport bridge for FreeType + HarfBuzz
│   └── tr.h              Minimal C header for text rendering
├── fonts/                Bundled fonts
├── protocols/            Custom Wayland protocol XMLs
├── build.zig             Build system (pkg-config discovery)
├── build.zig.zon         Zig package manifest
├── shell.nix             NixOS development shell
└── configuration.nix     System-wide package installation
```

</details>
