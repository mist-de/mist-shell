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
    libxkbcommon
    freetype
    harfbuzz
    pkg-config

    # Compositor for testing
    river
  ];

  shellHook = ''
    echo "Mist DE development shell"
    echo "Zig $(zig version)"
    echo ""
    echo "Run: zig build -Doptimize=ReleaseFast -- -lwayland-client -lxkbcommon -lfreetype -lharfbuzz"
    echo "Then: ./zig-out/bin/mist-bar"
  '';
}
