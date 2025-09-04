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
  userGroup = if pkgs.stdenv.isDarwin then "staff" else "users";

  # Helper script for project setup
  devSetupScript = pkgs.writeShellScriptBin "dev-setup" ''
    echo "🚀 Development Project Setup"
    echo "============================="

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
            echo "Setting up development configuration files for ${name}..."
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
            cp "${homeDir}/nixfiles/scripts/git-manager/gm.nu" "$PROJECT_DIR/" 2>/dev/null && echo "✅ Copied gm.nu" || echo "⚠️  gm.nu not found"

            # Set permissions and ownership
            chmod u+w "$PROJECT_DIR/.envrc" "$PROJECT_DIR/flake.nix" 2>/dev/null || true
            chmod +x "$PROJECT_DIR/startup.nu" "$PROJECT_DIR/gm.nu" 2>/dev/null || true
            if command -v chown >/dev/null 2>&1; then
              if [[ "$OSTYPE" == "darwin"* ]]; then
                chown -R ${username}:staff "$PROJECT_DIR/" 2>/dev/null || true
              else
                chown -R ${username}:users "$PROJECT_DIR/" 2>/dev/null || true
              fi
            fi
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
    # Core development tools + project-specific packages
    environment.systemPackages = with pkgs;
      [
        # Core development tools
        git
        gh
        direnv
        nix-direnv
        firebase-tools
        flutter # Includes Dart SDK

        # Development utilities
        curl
        wget
        jq
        tree

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

      # Create dev directory structure
      mkdir -p ${homeDir}/dev
      
      # Set ownership, but don't fail if chown doesn't work
      chown ${username}:${userGroup} ${homeDir}/dev 2>/dev/null || echo "Warning: Could not set ownership of ${homeDir}/dev"

      echo "Development environment setup complete!"
      echo "Run 'dev-setup' to clone repositories and setup project files."
    '';
  };
}
