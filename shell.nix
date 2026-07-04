{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Zig toolchain
    zig
    zls

    # System libraries for Mist
    wayland
    wayland-scanner
    wayland-protocols
    wlroots_0_20
    libxkbcommon
    freetype
    harfbuzz
    pixman
    fontconfig
    basu

    # Compositor for testing
    river

    # Build tools
    pkg-config
    gcc
    gnumake
    cmake
  ];

  shellHook = ''
    echo "Mist DE development shell"
    echo "Zig $(zig version)"
    echo ""
    echo "Available: river $(river -version 2>/dev/null || echo 'not in PATH')"
    echo "wayland, freetype, harfbuzz, pixman, basu, fontconfig, xkbcommon, wlroots"
  '';
}
