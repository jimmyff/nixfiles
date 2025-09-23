{
  inputs,
  pkgs,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.development;

  # Cross-platform home directory
  homeDir =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # Cross-platform user group
  userGroup =
    if pkgs.stdenv.isDarwin
    then "staff"
    else "users";

  # Helper script for project setup
  devSetupScript = pkgs.writeShellScriptBin "dev-setup" ''
    echo "🚀 Development Project Setup"
    echo "============================="
    echo ""

    # Check Flutter and Android SDK installation (only if Android is enabled)
    ${lib.optionalString (config.android.enable or false) ''
      echo "📱 Checking Flutter and Android SDK installation..."

      ERRORS=""

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
    echo ""

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

                    # Checkout main branch for all submodules to avoid detached HEAD state
                    echo "🌿 Checking out main branch for submodules..."
                    git submodule foreach git checkout main
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

            cp "$PROJECT_SOURCE/.envrc" "$PROJECT_DIR/" 2>/dev/null && echo "✅ Copied .envrc" || echo "⚠️  .envrc not found"
            cp "$PROJECT_SOURCE/startup.nu" "$PROJECT_DIR/" 2>/dev/null && echo "✅ Copied startup.nu" || echo "⚠️  startup.nu not found"
            cp "$PROJECT_SOURCE/flake.nix" "$PROJECT_DIR/" 2>/dev/null && echo "✅ Copied flake.nix" || echo "⚠️  flake.nix not found"

            # Setup development scripts via symlinks
            nu -c 'print $"(ansi purple_bold)🔗 Setting up development scripts for ${name}...(ansi reset)"'
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                projectName: projectConfig:
                  if projectName == name
                  then
                    # Global scripts
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
                    ) (projectConfig.scripts.global or ["git-manager/gm.nu"])))
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
            chmod u+w "$PROJECT_DIR/.envrc" "$PROJECT_DIR/flake.nix" 2>/dev/null || true
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
      value = import (../../projects + "/${projectName}") {inherit pkgs lib;};
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
    environment.systemPackages = with pkgs;
      [
        # Core development tools
        git
        gh
        direnv
        nix-direnv
        firebase-tools
        google-cloud-sdk
        # Flutter and Android SDK are provided by Android Studio instead of Nix
        # This avoids iOS build issues where Xcode cannot write to read-only Flutter root
        # See: https://github.com/flutter/flutter/pull/155139

        # Development utilities
        curl
        wget
        jq
        tree
        lnav
        doppler
        entr

        # build tools
        cmake
        gcc

        # Project setup helper
        devSetupScript
      ]
      ++ projectPackages;

    # Enable nix-direnv globally
    programs.direnv = {
      enable = true;
      package = pkgs.direnv;
      silent = false;
      loadInNixShell = true;
      settings = {
        hide_env_diff = true;
      };
      nix-direnv = {
        enable = true;
        package = pkgs.nix-direnv;
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
