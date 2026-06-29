# Shared devshell utilities for project flakes
# Used by: osdn, escp, rocket-kit, cache
rec {
  # Iterate devShells across all supported systems
  eachSystem = f:
    builtins.listToAttrs (map (system: {
      name = system;
      value = {default = f system;};
    }) ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"]);

  # Darwin fixes for the nixpkgs 25.05 darwin SDK changes. Two distinct problems:
  #
  # 1. PATH shadowing — nix packages place their own version of a system binary
  #    ahead of /usr/bin. We shadow them back with thin wrappers:
  #    - base64: coreutils shadows /usr/bin/base64, breaking CocoaPods.
  #    - xcrun:  xcbuild (pulled in transitively by cmake) shadows /usr/bin/xcrun.
  #
  # 2. xcode-select shim dispatch — bare Apple tools (install_name_tool, lipo,
  #    otool, strip, cc, clang, …) are /usr/bin shims that dispatch via
  #    DEVELOPER_DIR. The devshell's DEVELOPER_DIR/SDKROOT point at the SDK-only
  #    nix apple-sdk (no cctools/clang), so the shims fail with "tool not found".
  #    darwinPathHook unsets both so every shim falls back to the real Xcode
  #    toolchain. This is sturdier than per-tool wrappers: it also covers tools we
  #    never wrapped (lipo/otool/strip) — e.g. Flutter's native-assets build calls
  #    install_name_tool/lipo/otool by bare name.
  #
  # writeScriptBin uses #!/bin/sh (not writeShellScriptBin) because Flutter runs
  # `arch -arm64e xcrun ...`, which needs an interpreter with an arm64e slice;
  # nix's bash lacks one, macOS /bin/sh has it.
  darwinWrappers = pkgs: {
    base64 = pkgs.writeScriptBin "base64" ''
      #!/bin/sh
      exec /usr/bin/base64 "$@"
    '';
    xcrun = pkgs.writeScriptBin "xcrun" ''
      #!/bin/sh
      exec /usr/bin/xcrun "$@"
    '';
  };

  # Prepend the shadowing wrappers to PATH, then unset the nix apple-sdk env vars
  # so /usr/bin Apple-tool shims dispatch to Xcode. Done in shellHook because
  # buildInputs ordering doesn't guarantee PATH priority over transitive deps
  # (e.g. cmake propagates xcbuild's xcrun), and nix sets DEVELOPER_DIR/SDKROOT
  # during shell construction — shellHook runs after, so this is the reliable seam.
  darwinPathHook = pkgs: let
    wrappers = darwinWrappers pkgs;
  in
    pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
      export PATH="${wrappers.base64}/bin:${wrappers.xcrun}/bin:$PATH"
      unset DEVELOPER_DIR SDKROOT
    '';

  # Shell-hook tail: render the glitter workspace overview from the worktree root.
  # No-ops cleanly when glitter isn't on PATH.
  overviewHook = ''
    command -v glitter >/dev/null 2>&1 && glitter overview --compact || true
  '';

  # Shared devShell builder for the common project shape. Returns the full flake
  # `outputs` attrset ({ devShells = …; }) so a project flake's outputs can be just
  # `mkDevShell { inherit nixpkgs-stable; name = "Foo"; }`.
  #   nixpkgs-stable : stable nixpkgs input (provides legacyPackages.<system>)
  #   name           : display name shown in the shell banner
  #   extraPackages  : pkgs -> [ derivations ] added to the shell (default none)
  #   extraHook      : extra shellHook snippet inserted before the overview
  #   noCC           : use mkShellNoCC (default) vs mkShell
  mkDevShell = {
    nixpkgs-stable,
    name,
    extraPackages ? (_: []),
    extraHook ? "",
    noCC ? true,
  }: {
    devShells = eachSystem (system: let
      pkgs = nixpkgs-stable.legacyPackages.${system};
      mkShellFn =
        if noCC
        then pkgs.mkShellNoCC
        else pkgs.mkShell;
    in
      mkShellFn {
        packages = extraPackages pkgs;
        shellHook = ''
          ${darwinPathHook pkgs}
          echo "🚀 ${name} dev environment"
          ${extraHook}
          ${overviewHook}
        '';
      });
  };

}
