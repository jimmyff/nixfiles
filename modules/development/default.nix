{
  inputs,
  pkgs-stable,
  pkgs-dev-tools,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.development;

  # Cross-platform home directory
  homeDir =
    if pkgs-stable.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # Cross-platform user group
  userGroup =
    if pkgs-stable.stdenv.isDarwin
    then "staff"
    else "users";

  # Helper script for project setup
  devSetupScript = pkgs-stable.writeShellScriptBin "dev-setup" ''
    echo "🚀 Development Project Setup"
    echo "============================="
    echo ""

    # Copy file only if content has changed (avoids unnecessary direnv reloads)
    copy_if_changed() {
      local src="$1" dest="$2" label="$3"
      if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        echo "  $label unchanged, skipping"
        return 1
      fi
      chmod u+w "$dest" 2>/dev/null || true
      cp "$src" "$dest"
      echo "  Copied $label"
      return 0
    }

    # Check Flutter and Android SDK installation (only if Android is enabled)
    ${lib.optionalString (config.android.enable or false) ''
      echo "📱 Checking Flutter and Android SDK installation..."

      ERRORS=""

      # Setup writable Flutter SDK for Android Studio (Darwin only)
      ${lib.optionalString pkgs-stable.stdenv.isDarwin ''
        WRITABLE_FLUTTER="${homeDir}/.local/share/flutter"
        if [ ! -d "$WRITABLE_FLUTTER" ]; then
          echo "📥 Cloning writable Flutter SDK for Android Studio compatibility..."
          echo "   This enables Android Studio to work with Flutter on macOS"
          echo "   (Terminal builds will continue using Nix-managed Flutter)"
          mkdir -p "${homeDir}/.local/share"
          git clone https://github.com/flutter/flutter.git "$WRITABLE_FLUTTER" --depth 1 --branch stable
          if [ -d "$WRITABLE_FLUTTER" ]; then
            echo "✅ Writable Flutter SDK cloned to $WRITABLE_FLUTTER"
          else
            echo "❌ ERROR: Failed to clone Flutter SDK"
            ERRORS="1"
          fi
        else
          echo "✅ Writable Flutter SDK found at $WRITABLE_FLUTTER (for Android Studio)"
        fi
      ''}

      # Check for nix-managed Flutter first, then fall back to manual installation
      if command -v flutter >/dev/null 2>&1; then
        FLUTTER_PATH=$(which flutter)
        echo "✅ Flutter SDK found at $FLUTTER_PATH (nix-managed)"
      elif [ -d "${homeDir}/.local/share/flutter" ]; then
        echo "✅ Flutter SDK found at ${homeDir}/.local/share/flutter (manual installation)"
      else
        echo "❌ ERROR: Flutter SDK not found"
        echo "   Flutter should be available via nix-managed packages or manual installation"
        ERRORS="1"
      fi

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
    if [ -d "$GLOBAL_TOOLS_SOURCE/glitter" ]; then
      echo "✨ Building glittering..."
      (cd "$GLOBAL_TOOLS_SOURCE/glitter" && CGO_ENABLED=0 go build -o "${homeDir}/.local/bin/glittering" .) && echo "✅ Built glittering" || echo "❌ Failed to build glittering"
    fi

    # Link nu wrappers
    if [ -f "$GLOBAL_TOOLS_SOURCE/glitter/glitter.nu" ]; then
      ln -sf "$GLOBAL_TOOLS_SOURCE/glitter/glitter.nu" "${homeDir}/.local/bin/glitter" && echo "🔗 Linked glitter" || echo "❌ Failed to link glitter"
    fi
    nu -c 'print $"(ansi dark_gray_dimmed)────────────────────────────────────────(ansi reset)"'

    cd ${homeDir}/Projects || { echo "Error: ~/Projects directory not found"; exit 1; }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
        name: project:
          lib.optionalString (project.repo != null) ''
            if [ ! -d "${name}/workspace" ] || [ ! -d "${name}/workspace/.git" ]; then
              echo ""
              echo "📁 Setting up ${name}..."

              # Create project directory if it doesn't exist
              mkdir -p "${name}"

              # Remove workspace directory if it exists but isn't a git repo
              if [ -d "${name}/workspace" ] && [ ! -d "${name}/workspace/.git" ]; then
                echo "Removing non-git workspace directory ${name}/workspace..."
                rm -rf "${name}/workspace"
              fi

              # Clone into workspace subdirectory
              if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
                echo "Using GitHub CLI to clone ${project.repo}"
                gh repo clone ${project.repo} ${name}/workspace
              else
                echo "Using git to clone ${project.repo}"
                git clone ${project.repo} ${name}/workspace
              fi

              if [ -d "${name}/workspace" ] && [ -d "${name}/workspace/.git" ]; then
                echo "✅ ${name} cloned successfully"

                # Initialize git submodules if they exist
                cd "${name}/workspace"
                if [ -f .gitmodules ]; then
                  echo "🔄 Initializing git submodules..."
                  if git submodule update --init --recursive; then
                    echo "✅ Submodules initialized successfully"

                    # Checkout default branch for all submodules to avoid detached HEAD state
                    echo "🌿 Checking out default branch for submodules..."
                    git submodule foreach '
                      branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed "s@^refs/remotes/origin/@@")
                      if [ -z "$branch" ]; then
                        git remote set-head origin --auto >/dev/null 2>&1
                        branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed "s@^refs/remotes/origin/@@")
                      fi
                      if [ -n "$branch" ]; then
                        git checkout "$branch"
                      else
                        echo "⚠️  Could not determine default branch for $name, staying detached"
                      fi
                    '
                  else
                    echo "❌ Failed to initialize submodules"
                  fi
                fi

                # Initialize git LFS if .gitattributes contains LFS references
                if [ -f .gitattributes ] && grep -q "filter=lfs" .gitattributes 2>/dev/null; then
                  echo "📦 Initializing git LFS..."

                  # Install LFS hooks locally (avoid global config issues)
                  git lfs install --local

                  # Fetch LFS objects instead of pulling (more reliable)
                  echo "📥 Downloading LFS objects..."
                  git lfs fetch --all
                  git lfs checkout

                  # If that fails, try alternative approach
                  if [ $? -ne 0 ]; then
                    echo "⚠️  LFS checkout failed, trying alternative approach..."
                    # Reset any problematic state
                    git reset --hard HEAD
                    git lfs fetch --all
                    git lfs checkout --force
                  fi
                fi
                cd ../..

              else
                echo "❌ Failed to clone ${name}"
              fi
            else
              echo "✅ ${name} already exists"
            fi

            # Always copy/update development configuration files
            nu -c 'print $"(ansi blue_bold)📁 Setting up development configuration for ${name}...(ansi reset)"'
            PROJECT_DIR="${homeDir}/Projects/${name}"
            PROJECT_SOURCE="${homeDir}/nixfiles/projects/${name}"
            mkdir -p "$PROJECT_DIR"

            # Fix ownership of project directory
            if command -v chown >/dev/null 2>&1; then
              if [[ "$OSTYPE" == "darwin"* ]]; then
                chown -R ${username}:staff "$PROJECT_DIR" 2>/dev/null || true
              else
                chown -R ${username}:users "$PROJECT_DIR" 2>/dev/null || true
              fi
            fi

            # Copy .envrc with warning comment (only if changed)
            if [ -f "$PROJECT_SOURCE/.envrc" ]; then
              TMPFILE=$(mktemp)
              {
                echo "# NOTE: Copied version: original is in nixfiles/projects/${name}/.envrc"
                echo "# This file is read-only to prevent accidental edits. Edit the original in nixfiles instead."
                echo ""
                cat "$PROJECT_SOURCE/.envrc"
              } > "$TMPFILE"
              copy_if_changed "$TMPFILE" "$PROJECT_DIR/.envrc" ".envrc"
              rm -f "$TMPFILE"
            else
              echo "⚠️  .envrc not found"
            fi

            if [ -f "$PROJECT_SOURCE/startup.nu" ]; then
              copy_if_changed "$PROJECT_SOURCE/startup.nu" "$PROJECT_DIR/startup.nu" "startup.nu"
            else
              echo "⚠️  startup.nu not found"
            fi

            # Copy flake.nix with warning comment (only if changed)
            if [ -f "$PROJECT_SOURCE/flake.nix" ]; then
              TMPFILE=$(mktemp)
              {
                echo "# NOTE: Copied version: original is in nixfiles/projects/${name}/flake.nix"
                echo "# This file is read-only to prevent accidental edits. Edit the original in nixfiles instead."
                echo ""
                cat "$PROJECT_SOURCE/flake.nix"
              } > "$TMPFILE"
              copy_if_changed "$TMPFILE" "$PROJECT_DIR/flake.nix" "flake.nix"
              rm -f "$TMPFILE"
            else
              echo "⚠️  flake.nix not found"
            fi

            # Copy shared devshell-utils.nix with warning comment (only if changed)
            UTILS_SOURCE="${homeDir}/nixfiles/projects/devshell-utils.nix"
            if [ -f "$UTILS_SOURCE" ]; then
              TMPFILE=$(mktemp)
              {
                echo "# NOTE: Copied version: original is in nixfiles/projects/devshell-utils.nix"
                echo "# This file is read-only to prevent accidental edits. Edit the original in nixfiles instead."
                echo ""
                cat "$UTILS_SOURCE"
              } > "$TMPFILE"
              copy_if_changed "$TMPFILE" "$PROJECT_DIR/devshell-utils.nix" "devshell-utils.nix"
              rm -f "$TMPFILE"
            else
              echo "⚠️  devshell-utils.nix not found"
            fi

            # Copy flake.lock to keep it in sync (Nix doesn't support symlinks for flake.lock)
            if [ -f "$PROJECT_SOURCE/flake.lock" ]; then
              if [ -f "$PROJECT_DIR/flake.lock" ]; then
                if ! cmp -s "$PROJECT_SOURCE/flake.lock" "$PROJECT_DIR/flake.lock"; then
                  echo "❌ ERROR: flake.lock files differ between nixfiles and project directory"
                  echo "   Source: $PROJECT_SOURCE/flake.lock"
                  echo "   Dest:   $PROJECT_DIR/flake.lock"
                  echo "   Please manually sync these files to avoid losing local changes."
                  exit 1
                fi
                echo "  flake.lock unchanged, skipping"
              else
                cp "$PROJECT_SOURCE/flake.lock" "$PROJECT_DIR/flake.lock" && echo "  Copied flake.lock" || echo "⚠️  Failed to copy flake.lock"
              fi
            fi

            # Setup development scripts via symlinks
            nu -c 'print $"(ansi purple_bold)🔗 Setting up development scripts for ${name}...(ansi reset)"'
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                projectName: projectConfig:
                  if projectName == name
                  then
                    # Global scripts (symlinked to project dir)
                    (lib.concatStringsSep "\n" (map (
                      scriptPath: let
                        scriptName = lib.last (lib.splitString "/" scriptPath);
                      in ''
                        SCRIPT_SOURCE="${homeDir}/nixfiles/scripts/${scriptPath}"
                        SCRIPT_TARGET="$PROJECT_DIR/${scriptName}"
                        if [ -f "$SCRIPT_SOURCE" ]; then
                          ln -sf "$SCRIPT_SOURCE" "$SCRIPT_TARGET" && echo "✅ Linked ${scriptName}" || echo "⚠️  Failed to link ${scriptName}"
                          chmod +x "$SCRIPT_TARGET" 2>/dev/null || true
                        else
                          echo "⚠️  Global script not found: ${scriptPath}"
                        fi
                      ''
                    ) (projectConfig.scripts.global or [])))
                    +
                    # Local scripts
                    (lib.concatStringsSep "\n" (map (
                      scriptName: ''
                        LOCAL_SCRIPT_SOURCE="$PROJECT_SOURCE/${scriptName}"
                        LOCAL_SCRIPT_TARGET="$PROJECT_DIR/${scriptName}"
                        if [ -f "$LOCAL_SCRIPT_SOURCE" ]; then
                          ln -sf "$LOCAL_SCRIPT_SOURCE" "$LOCAL_SCRIPT_TARGET" && echo "✅ Linked local ${scriptName}" || echo "⚠️  Failed to link local ${scriptName}"
                          chmod +x "$LOCAL_SCRIPT_TARGET" 2>/dev/null || true
                        else
                          echo "⚠️  Local script not found: ${scriptName}"
                        fi
                      ''
                    ) (projectConfig.scripts.local or [])))
                  else ""
              )
              enabledProjects
            )}

            # Set permissions and ownership
            chmod u-w "$PROJECT_DIR/.envrc" 2>/dev/null || true
            chmod u-w "$PROJECT_DIR/flake.nix" 2>/dev/null || true
            chmod u-w "$PROJECT_DIR/devshell-utils.nix" 2>/dev/null || true
            chmod +x "$PROJECT_DIR/startup.nu" 2>/dev/null || true
            if command -v chown >/dev/null 2>&1; then
              if [[ "$OSTYPE" == "darwin"* ]]; then
                chown -R ${username}:staff "$PROJECT_DIR/" 2>/dev/null || true
              else
                chown -R ${username}:users "$PROJECT_DIR/" 2>/dev/null || true
              fi
            fi

            nu -c 'print $"(ansi dark_gray_dimmed)────────────────────────────────────────(ansi reset)"'
          ''
      )
      enabledProjects)}

    echo ""
    echo "🎉 Project setup complete!"
    echo "Navigate to ~/Projects/<project> and run 'direnv allow' to enable the development environment."
  '';

  # Import enabled project modules
  enabledProjects = lib.listToAttrs (map (projectName: {
      name = projectName;
      value = import (../../projects + "/${projectName}") {pkgs = pkgs-stable; inherit lib;};
    })
    cfg.projects);

  # Collect all packages from enabled projects
  projectPackages = lib.flatten (lib.mapAttrsToList (_: project: project.packages or []) enabledProjects);
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

    projects = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of development projects to enable";
      example = ["jimmyff-website" "rocket-kit"];
    };
  };

  config = lib.mkIf cfg.enable {
    # Core development tools + project-specific packages + platform packages
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
        pkgs-stable.firebase-tools # Pinned to stable due to unstable build issues
        pkgs-dev-tools.google-cloud-sdk
        pkgs-dev-tools.entr
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
      ++ projectPackages;

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

      # Create Projects directory structure
      mkdir -p ${homeDir}/Projects

      # Set ownership, but don't fail if chown doesn't work
      chown ${username}:${userGroup} ${homeDir}/Projects 2>/dev/null || echo "Warning: Could not set ownership of ${homeDir}/Projects"

      echo "Development environment setup complete!"
      echo "Run 'dev-setup' to clone repositories and setup project files."
    '';
  };
}
