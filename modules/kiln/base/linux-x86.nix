# Linux x86_64 base module for mkKiln.
# Provides core CLI tools, build toolchain, and GTK stack for Flutter Linux
# desktop builds. Flutter and Android SDK are NOT included — those are
# parameterized via mkKiln's flutterPackage and androidSdkPackages.
{ pkgs, inputs }:
let
  common = import ./common.nix { inherit pkgs; };
in
{
  system = "x86_64-linux";
  label = "linux-x86";

  corePackages = common.coreCliPackages ++ (with pkgs; [
    # Linux-specific
    fontconfig tzdata sqlite

    # Build toolchain (Flutter Linux desktop)
    cmake ninja pkg-config gcc

    # GTK stack
    gtk3 glib pango cairo gdk-pixbuf atk harfbuzz
    webkitgtk_4_1 libsoup_3 libsecret
  ]);

  baseEnv = common.coreCliEnv // {
    # Dart FFI uses dlopen("libsqlite3.so") which needs a standard library
    # path. Nix store paths aren't searched by default.
    LD_LIBRARY_PATH = "${pkgs.sqlite.out}/lib";
  };

  # Logical groupings for documentation and future layer optimization.
  # streamLayeredImage doesn't consume these directly (only maxLayers).
  layerGroups = {
    gtkStack = with pkgs; [ gtk3 glib pango cairo gdk-pixbuf atk harfbuzz ];
    buildTools = with pkgs; [ cmake ninja pkg-config gcc ];
  };
}
