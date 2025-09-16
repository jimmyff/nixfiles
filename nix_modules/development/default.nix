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

  # Platform-specific packages
  platformPackages = with pkgs;
    {
      darwin =
        [
          ruby
          cocoapods
        ]
        ++ lib.optionals (pkgs.stdenv.system == "x86_64-darwin") [
          android-studio
        ];
      linux = [
        android-studio
      ];
    }.${
      if pkgs.stdenv.isDarwin
      then "darwin"
      else "linux"
    };

  # Helper script for project setup
  devSetupScript = pkgs.writeShellScriptBin "dev-setup" ''
    echo "🚀 Development Project Setup"
    echo "============================="
    echo ""

    # Check Flutter and Android SDK installation
    echo "📱 Checking Flutter and Android SDK installation..."
    
    ERRORS=""
    
    if [ ! -d "${homeDir}/.local/share/flutter" ]; then
      echo "❌ ERROR: Flutter SDK not found at ${homeDir}/.local/share/flutter"
      echo "   Please install Flutter via Android Studio or manually"
      ERRORS="1"
    else
      echo "✅ Flutter SDK found at ${homeDir}/.local/share/flutter"
    fi
    
    if [ ! -d "${homeDir}/.local/share/android/sdk" ]; then
      echo "❌ ERROR: Android SDK not found at ${homeDir}/.local/share/android/sdk"
      echo "   Please install Android SDK via Android Studio"
      ERRORS="1"
    else
      echo "✅ Android SDK found at ${homeDir}/.local/share/android/sdk"
      
      # Check for command-line tools specifically
      if [ ! -d "${homeDir}/.local/share/android/sdk/cmdline-tools" ]; then
        echo "⚠️  WARNING: Android command-line tools not found"
        echo "   In Android Studio: Tools → SDK Manager → SDK Tools → Android SDK Command-line Tools"
      else
        echo "✅ Android command-line tools found"
      fi
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

    # Activate Dart tooling if dart is available
    nu -c 'print $"(ansi cyan_bold)🎯 Setting up Dart tooling...(ansi reset)"'
    if command -v dart >/dev/null 2>&1; then
      echo "   Activating cider (CI for Dart)"
      dart pub global activate cider
      echo "   ✅ Dart tooling activation complete"
    else
      echo "   ⚠️  Dart not found, skipping Dart tooling setup"
    fi
    nu -c 'print $"(ansi dark_gray_dimmed)────────────────────────────────────────(ansi reset)"'
    echo ""

    cd ${homeDir}/dev || { echo "Error: ~/dev directory not found"; exit 1; }

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
            PROJECT_DIR="${homeDir}/dev/${name}"
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
    echo "Navigate to ~/dev/<project> and run 'direnv allow' to enable the development environment."
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

        # Project setup helper
        devSetupScript
      ]
      ++ projectPackages
      ++ platformPackages;

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

    # Flutter and Android SDK environment variables for Android Studio installation
    environment.variables = {
      ANDROID_HOME = "${homeDir}/.local/share/android/sdk";
      FLUTTER_ROOT = "${homeDir}/.local/share/flutter";
      PUB_CACHE = "${homeDir}/.cache/flutter/pub-cache";
    };

    # NOTE: nix-darwin only supports hardcoded activation script names. Custom names are silently ignored.
    # Supported names: preActivation, postActivation, extraActivation, and ~20 system-specific ones.
    # See: https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/activation-scripts.nix
    system.activationScripts.postActivation.text = ''
      echo "Setting up development environment..."

      # Create dev directory structure
      mkdir -p ${homeDir}/dev

      # Create Flutter pub cache directory (this is just a cache, safe to create)
      mkdir -p ${homeDir}/.cache/flutter/pub-cache

      # Set ownership, but don't fail if chown doesn't work
      chown ${username}:${userGroup} ${homeDir}/dev 2>/dev/null || echo "Warning: Could not set ownership of ${homeDir}/dev"
      chown -R ${username}:${userGroup} ${homeDir}/.cache/flutter 2>/dev/null || echo "Warning: Could not set ownership of ${homeDir}/.cache/flutter"

      echo "Development environment setup complete!"
      echo "Run 'dev-setup' to clone repositories and setup project files."
    '';
  };
}
