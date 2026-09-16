{
  inputs,
  pkgs-stable,
  pkgs-dev-tools,
  pkgs-dev-flutter,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.development;
  isDarwin = pkgs-stable.stdenv.hostPlatform.isDarwin;

  # Flutter release from nixpkgs. macOS pins its writable clone to this tag.
  flutterVersion = pkgs-dev-flutter.flutter.version;

  # Cross-platform home directory
  homeDir =
    if pkgs-stable.stdenv.hostPlatform.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # Cross-platform user group
  userGroup =
    if pkgs-stable.stdenv.hostPlatform.isDarwin
    then "staff"
    else "users";

  # Helper script for project setup
  devSetupScript = pkgs-stable.writeShellScriptBin "dev-setup" ''
    echo "🚀 Development Project Setup"
    echo "============================="
    echo ""

    ${lib.optionalString (config.dart.enable && isDarwin) ''
      # macOS: writable Flutter clone (Xcode writes into it), pinned to the nixpkgs release.
      FLUTTER_SDK="${homeDir}/.local/share/flutter"
      FLUTTER_WANT="${flutterVersion}"
      echo "📱 Flutter SDK: $FLUTTER_SDK (writable clone, pinned to nixpkgs $FLUTTER_WANT)"
      if [ ! -d "$FLUTTER_SDK/.git" ]; then
        echo "   Cloning Flutter $FLUTTER_WANT..."
        mkdir -p "${homeDir}/.local/share"
        git clone -q --depth 1 --branch "$FLUTTER_WANT" https://github.com/flutter/flutter.git "$FLUTTER_SDK" \
          || { echo "❌ Failed to clone Flutter $FLUTTER_WANT"; exit 1; }
      else
        FLUTTER_HAVE=$(git -C "$FLUTTER_SDK" describe --tags --exact-match 2>/dev/null || echo unknown)
        if [ "$FLUTTER_HAVE" = "$FLUTTER_WANT" ]; then
          echo "   ✅ Flutter $FLUTTER_HAVE matches nixpkgs"
        else
          echo "   🔄 Switching Flutter $FLUTTER_HAVE → $FLUTTER_WANT (detached at the release tag)"
          git -C "$FLUTTER_SDK" fetch -q --depth 1 origin "+refs/tags/$FLUTTER_WANT:refs/tags/$FLUTTER_WANT" \
            && git -C "$FLUTTER_SDK" checkout -q --detach "refs/tags/$FLUTTER_WANT" \
            || { echo "❌ Failed to switch Flutter to $FLUTTER_WANT (offline?)"; exit 1; }
        fi
      fi
      # Build the tool cache now; this also refreshes the version file the wrappers check.
      flutter --version >/dev/null 2>&1 || echo "   ⚠️  Flutter tool cache build failed; run 'flutter doctor'"
      nu -c 'print $"(ansi dark_gray_dimmed)────────────────────────────────────────(ansi reset)"'
    ''}

    # Check Flutter and Android SDK installation (only if Android is enabled)
    ${lib.optionalString (config.android.enable or false) ''
      echo "📱 Checking Flutter and Android SDK installation..."

      ERRORS=""

      if command -v flutter >/dev/null 2>&1; then
        echo "✅ Flutter SDK found at $(which flutter)"
      else
        echo "❌ ERROR: Flutter SDK not found"
        echo "   Flutter should be available via nix-managed packages or manual installation"
        ERRORS="1"
      fi

      ${lib.optionalString isDarwin ''
        # Point Flutter at the Nix JDK (Linux does this at activation).
        flutter config --jdk-dir="${pkgs-dev-flutter.zulu17}" >/dev/null 2>&1 \
          || echo "⚠️  WARNING: Could not point Flutter at the Nix JDK"
      ''}

      # Check for Nix-managed Android SDK
      if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME" ]; then
        echo "✅ Android SDK found at $ANDROID_HOME (Nix-managed)"

        # Check for command-line tools specifically
        if [ ! -d "$ANDROID_HOME/cmdline-tools" ]; then
          echo "⚠️  WARNING: Android command-line tools not found in Nix-managed SDK"
          echo "   This may indicate an issue with the android-nixpkgs configuration"
        else
          echo "✅ Android command-line tools found"
        fi
      else
        echo "❌ ERROR: Android SDK not found via ANDROID_HOME environment variable"
        echo "   Please ensure android.enable = true in your Nix configuration"
        ERRORS="1"
      fi

      if [ ! -z "$ERRORS" ]; then
        echo ""
        echo "🚨 SETUP ERRORS DETECTED 🚨"
        echo "Please fix the above errors before proceeding with development."
        echo "See docs/development.md for installation instructions."
        exit 1
      fi

      echo "✅ All Flutter and Android SDK checks passed!"
      echo ""
    ''}

    # Display Dart and Flutter versions and activate tooling
    nu -c 'print $"(ansi cyan_bold)🎯 Setting up Dart tooling...(ansi reset)"'
    if command -v dart >/dev/null 2>&1; then
      echo "   📦 Dart version: $(dart --version 2>&1)"
      if command -v flutter >/dev/null 2>&1; then
        echo "   📦 Flutter version: $(flutter --version 2>/dev/null | head -1)"
      fi
      echo "   Activating cider (CI for Dart)"
      dart pub global activate cider
      echo "   ✅ Dart tooling activation complete"
    else
      echo "   ⚠️  Dart not found, skipping Dart tooling setup"
    fi
    nu -c 'print $"(ansi dark_gray_dimmed)────────────────────────────────────────(ansi reset)"'

    # Build global tools to ~/.local/bin
    mkdir -p "${homeDir}/.local/bin"
    GLOBAL_TOOLS_SOURCE="${homeDir}/nixfiles/scripts"

    # Build Go tools
    if [ -d "$GLOBAL_TOOLS_SOURCE/glittering" ]; then
      echo "✨ Building glittering..."
      (cd "$GLOBAL_TOOLS_SOURCE/glittering" && CGO_ENABLED=0 go build -o "${homeDir}/.local/bin/glittering" .) && echo "✅ Built glittering" || echo "❌ Failed to build glittering"
    fi

    # Link nu wrappers
    if [ -f "$GLOBAL_TOOLS_SOURCE/glittering/glitter.nu" ]; then
      ln -sf "$GLOBAL_TOOLS_SOURCE/glittering/glitter.nu" "${homeDir}/.local/bin/glitter" && echo "🔗 Linked glitter" || echo "❌ Failed to link glitter"
    fi
    nu -c 'print $"(ansi dark_gray_dimmed)────────────────────────────────────────(ansi reset)"'

    # Attach a fresh submodule clone (cwd) to its branch at the pin, not origin's tip.
    attach_at_pin() {
      local pin cands branch
      pin=$(git rev-parse HEAD)
      cands=$(git for-each-ref --contains "$pin" --format='%(refname:strip=3)' 'refs/remotes/origin/*' | grep -vx HEAD)
      branch=$(echo "$cands" | grep -xm1 main || echo "$cands" | head -1)
      if [ -z "$branch" ]; then
        echo "  ⚠️  $1: no origin branch contains the pinned commit; left detached"
      elif git show-ref --verify --quiet "refs/heads/$branch" && [ "$(git rev-list --count "origin/$branch..$branch")" -gt 0 ]; then
        echo "  ⚠️  $1: local $branch has unpushed commits; left detached at the pin"
      else
        git checkout -q -B "$branch" "$pin" || { echo "  ❌ $1: checkout $branch at pin failed"; return 1; }
        git rev-parse --abbrev-ref "$branch@{upstream}" >/dev/null 2>&1 \
          || git branch -q --set-upstream-to="origin/$branch" "$branch"
      fi
    }

    cd ${homeDir}/projects || { echo "Error: ~/projects directory not found"; exit 1; }

    # Per project: bare-clone the repo and check out a flat default-branch worktree.
    # The devshell flake now lives in the repo, so there is nothing to copy — Nix
    # snapshots only git-tracked source, cached by commit. Idempotent: a re-run with
    # .bare present just re-ensures the worktree, submodules, LFS, and direnv allow.
    ${lib.concatStringsSep "\n" (map (
        name: let
          repo =
            repos.${name}
            or (throw "development.projects: no repo URL for '${name}' in projects/repos.nix");
        in ''
          echo ""
          echo "📁 ${name}"
          PROJECT_DIR="${homeDir}/projects/${name}"
          mkdir -p "$PROJECT_DIR"

          # Fresh setup: bare clone, remote-tracking refspec, push.autoSetupRemote.
          if [ ! -d "$PROJECT_DIR/.bare" ]; then
            echo "  Bare-cloning ${repo}"
            git clone --bare "${repo}" "$PROJECT_DIR/.bare"
            git --git-dir="$PROJECT_DIR/.bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
            # Bare-cloned worktree branches have no upstream; this lets `git push` work without -u.
            git --git-dir="$PROJECT_DIR/.bare" config push.autoSetupRemote true
            printf 'gitdir: ./.bare\n' > "$PROJECT_DIR/.git"
          fi

          # Ensure the default-branch (main/master) worktree exists.
          DEFAULT=$(git --git-dir="$PROJECT_DIR/.bare" symbolic-ref --short HEAD)
          if [ ! -d "$PROJECT_DIR/$DEFAULT" ]; then
            # Fetches only move origin/*, so the local branch is stuck at the clone-time
            # commit. No worktree holds it yet, so fast-forward it before checkout.
            git --git-dir="$PROJECT_DIR/.bare" fetch -q origin \
              || echo "  ⚠️  Fetch failed (offline?); continuing with cached refs"
            if git --git-dir="$PROJECT_DIR/.bare" merge-base --is-ancestor "refs/heads/$DEFAULT" "refs/remotes/origin/$DEFAULT" 2>/dev/null; then
              git --git-dir="$PROJECT_DIR/.bare" update-ref "refs/heads/$DEFAULT" "refs/remotes/origin/$DEFAULT"
            else
              echo "  ⚠️  Local $DEFAULT is not an ancestor of origin/$DEFAULT; leaving it as-is"
            fi
            echo "  Adding worktree $DEFAULT"
            git -C "$PROJECT_DIR" worktree add "$DEFAULT" "$DEFAULT"
          fi

          WT="$PROJECT_DIR/$DEFAULT"
          if [ -d "$WT" ]; then
            cd "$WT"

            # Bare clones record no upstream for the default branch; set it so status shows behind.
            if [ -z "$(git config --get "branch.$DEFAULT.merge")" ]; then
              git branch -q --set-upstream-to="origin/$DEFAULT" "$DEFAULT" \
                && echo "  🔗 $DEFAULT now tracks origin/$DEFAULT"
            fi

            # Init missing submodules only; nested ones stay detached at their pin.
            if [ -f .gitmodules ]; then
              missing=$(git submodule status | sed -n 's/^-[0-9a-f]* \([^ ]*\).*/\1/p')
              if [ -n "$missing" ]; then
                echo "🔄 Initializing submodules..."
                if echo "$missing" | xargs git submodule update --init --recursive --; then
                  echo "$missing" | while read -r sm; do
                    (cd "$sm" && attach_at_pin "$sm")
                  done
                else
                  echo "❌ Failed to initialize submodules"
                fi
              fi
            fi

            # Git LFS, if the repo uses it.
            if [ -f .gitattributes ] && grep -q "filter=lfs" .gitattributes 2>/dev/null; then
              echo "📦 Fetching LFS objects..."
              git lfs install --local
              git lfs fetch --all
              git lfs checkout
            fi

            # Allow the committed devshell (no-op until the repo carries its flake/.envrc).
            if [ -f .envrc ] && command -v direnv >/dev/null 2>&1; then
              direnv allow .
            fi

            cd "${homeDir}/projects"
          else
            echo "❌ ${name}: worktree $DEFAULT missing after setup"
          fi

          nu -c 'print $"(ansi dark_gray_dimmed)────────────────────────────────────────(ansi reset)"'
        ''
      )
      cfg.projects)}

    echo ""
    echo "🎉 Project setup complete!"
    echo "Enter a project worktree (e.g. ~/projects/<project>/main) — direnv activates the devshell."
  '';

  # Project name -> repo URL map (replaces the old per-project default.nix modules).
  repos = import ../../projects/repos.nix;
in {
  imports = [
    ./android.nix
    ./dart.nix
    ./xcode.nix
    ./rust.nix
    ./mitmproxy.nix
    ./wireshark.nix
    ./docker.nix
    ./sops-wrappers.nix
  ];

  options.development = {
    enable = lib.mkEnableOption "development environment";

    google-cloud-sdk = lib.mkEnableOption "Google Cloud SDK" // { default = true; };
    firebase-tools = lib.mkEnableOption "Firebase CLI tools" // { default = true; };

    projects = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of development projects to enable";
      example = ["jimmyff-website" "rocket-kit"];
    };
  };

  config = lib.mkIf cfg.enable {
    # Core development tools + platform packages
    environment.systemPackages =
      [
        # Core development tools (stable)
        pkgs-stable.git
        pkgs-stable.gh
        # TODO: move direnv back to pkgs-stable once NixOS/nix#15638 lands
        # (Mach-O code signature corruption breaks fish test on darwin)
        pkgs-dev-tools.direnv
        pkgs-dev-tools.nix-direnv

        # Development utilities
        pkgs-dev-tools.lnav
        pkgs-dev-tools.go

        # On-demand secret decryption (sops + ssh-to-age for the age identity bootstrap)
        pkgs-stable.sops
        pkgs-stable.ssh-to-age

        # Basic CLI utilities (stable)
        pkgs-stable.curl
        pkgs-stable.wget
        pkgs-stable.jq
        pkgs-stable.tree

        # Project setup helper
        devSetupScript
      ]
      ++ (lib.optional cfg.google-cloud-sdk pkgs-dev-tools.google-cloud-sdk)
      ++ (lib.optional cfg.firebase-tools pkgs-stable.firebase-tools); # Pinned to stable due to unstable build issues

    # Enable nix-direnv globally
    programs.direnv = {
      enable = true;
      package = pkgs-dev-tools.direnv; # TODO: move back to pkgs-stable (NixOS/nix#15638)
      silent = false;
      loadInNixShell = true;
      settings = {
        hide_env_diff = true;
      };
      nix-direnv = {
        enable = true;
        package = pkgs-dev-tools.nix-direnv; # TODO: move back to pkgs-stable (NixOS/nix#15638)
      };
    };

    # NOTE: nix-darwin only supports hardcoded activation script names. Custom names are silently ignored.
    # Supported names: preActivation, postActivation, extraActivation, and ~20 system-specific ones.
    # See: https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/activation-scripts.nix
    system.activationScripts.postActivation.text = ''
      echo "Setting up development environment..."

      # Create projects directory structure
      mkdir -p ${homeDir}/projects

      # Set ownership, but don't fail if chown doesn't work
      chown ${username}:${userGroup} ${homeDir}/projects 2>/dev/null || echo "Warning: Could not set ownership of ${homeDir}/projects"

      echo "Development environment setup complete!"
      echo "Run 'dev-setup' to clone repositories and setup project files."
    '';
  };
}
