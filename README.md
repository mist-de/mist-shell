# Mist

> **Early development. Not stable. Expect rendering issues.**

A minimal Wayland desktop environment shell written in Zig. Pure software rendering via wl_shm. Zero GPU.

## Build

Requires [Nix](https://nixos.org/):

```sh
nix-shell --run "zig build -Doptimize=ReleaseFast -- -lwayland-client -lxkbcommon -lfreetype -lharfbuzz"
./zig-out/bin/mist-bar
```

## Status

| Component | Status |
|-----------|--------|
| Wayland layer shell (wl_shm) | Working |
| Smoothstep AA rendering | Working |
| FreeType + HarfBuzz text | Working |
| M3 color palette | Working |
| Workspace indicators | Working (live via ext-workspace) |
| Active window tracking | Working (live via zwlr-foreign-toplevel) |
| Resource rings | Working (placeholder data) |
| Input dispatch | Not implemented |
| D-Bus services | Not implemented |
| Auto-hide | Not implemented |

## Fonts

Bundled in `fonts/`: Inter, NotoSans Nerd Font, JetBrains Mono Nerd Font, Material Symbols Rounded.
