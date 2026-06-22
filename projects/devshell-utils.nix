# Shared devshell utilities for project flakes
# Used by: osdn, escp, rocket-kit, cache
rec {
  # Iterate devShells across all supported systems
  eachSystem = f:
    builtins.listToAttrs (map (system: {
      name = system;
      value = {default = f system;};
    }) ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"]);

  # Darwin wrappers for system binaries shadowed by Nix
  # base64: fixes CocoaPods compatibility (coreutils shadows /usr/bin/base64)
  # xcrun: fixes xcbuild dependency shadowing /usr/bin/xcrun
  # install_name_tool: Flutter's native-assets host code calls it by bare name
  #   (not via xcrun) to set dylib install names. The /usr/bin stub dispatches
  #   via DEVELOPER_DIR, which points at the SDK-only Nix apple-sdk (no cctools),
  #   so it fails with "tool not found". Unset → falls back to Xcode, like xcrun.
  # Uses writeScriptBin with #!/bin/sh (not writeShellScriptBin) because Flutter
  # invokes `arch -arm64e xcrun ...` which requires the interpreter to have an
  # arm64e slice. Nix's bash doesn't; macOS /bin/sh does.
  darwinWrappers = pkgs: {
    base64 = pkgs.writeScriptBin "base64" ''
      #!/bin/sh
      exec /usr/bin/base64 "$@"
    '';
    xcrun = pkgs.writeScriptBin "xcrun" ''
      #!/bin/sh
      unset DEVELOPER_DIR SDKROOT
      exec /usr/bin/xcrun "$@"
    '';
    install_name_tool = pkgs.writeScriptBin "install_name_tool" ''
      #!/bin/sh
      unset DEVELOPER_DIR SDKROOT
      exec /usr/bin/install_name_tool "$@"
    '';
  };

  # Prepend Darwin wrappers to PATH via shellHook.
  # buildInputs ordering does NOT guarantee PATH priority over transitive
  # dependencies (e.g. cmake propagates xcbuild which shadows xcrun).
  # shellHook runs after Nix constructs PATH, so this is the only reliable way.
  darwinPathHook = pkgs: let
    wrappers = darwinWrappers pkgs;
  in
    pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
      export PATH="${wrappers.base64}/bin:${wrappers.xcrun}/bin:${wrappers.install_name_tool}/bin:$PATH"
    '';

  # Common shellHook tail: run startup.nu
  commonShellHook = ''
    # Run startup script if it exists and nushell is available
    if [ -f startup.nu ] && command -v nu >/dev/null 2>&1 && nu -c "version" >/dev/null 2>&1; then
      nu startup.nu
    elif [ -f startup.nu ]; then
      echo ""
      echo "🔧 To start the development environment, run: ./startup.nu"
    fi
  '';
}
