# Shared devshell utilities for project flakes
# Used by: osdn, escp, rocket-kit, jotter
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
  };

  # Prepend Darwin wrappers to PATH via shellHook.
  # buildInputs ordering does NOT guarantee PATH priority over transitive
  # dependencies (e.g. cmake propagates xcbuild which shadows xcrun).
  # shellHook runs after Nix constructs PATH, so this is the only reliable way.
  darwinPathHook = pkgs: let
    wrappers = darwinWrappers pkgs;
  in
    pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
      export PATH="${wrappers.base64}/bin:${wrappers.xcrun}/bin:$PATH"
    '';

  # Doppler environment variable loading hook
  mkDopplerShellHook = {
    project,
    config ? "dev",
  }: ''
    # Load Doppler environment variables safely without eval
    set -a
    while IFS='=' read -r key value; do
      # Only export valid variable names and non-empty keys
      if [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        # Strip surrounding quotes if present
        value=''${value#\"}
        value=''${value%\"}
        export "$key"="$value"
      fi
    done < <(doppler secrets download --no-file --format env --project ${project} --config ${config})
    set +a
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
