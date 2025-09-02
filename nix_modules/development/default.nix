{ inputs, pkgs, lib, config, username, ... }:

let
  cfg = config.development;
  
  # Cross-platform home directory
  homeDir = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
  
  # Helper script for project setup
  devSetupScript = pkgs.writeShellScriptBin "dev-setup" ''
    echo "🚀 Development Project Setup"
    echo "============================="
    
    cd ${homeDir}/dev || { echo "Error: ~/dev directory not found"; exit 1; }
    
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: project: 
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
              git submodule update --init --recursive
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
            
            # Trigger system activation to setup development files
            echo "Setting up development configuration..."
            sudo nixos-rebuild switch --flake /etc/nixos#nixelbook --no-build-nix
          else
            echo "❌ Failed to clone ${name}"
          fi
        else
          echo "✅ ${name} already exists"
        fi
      ''
    ) enabledProjects)}
    
    echo ""
    echo "🎉 Project setup complete!"
    echo "Navigate to ~/dev/<project> and run 'direnv allow' to enable the development environment."
  '';
  
  # Import enabled project modules
  enabledProjects = lib.listToAttrs (map (projectName: {
    name = projectName;
    value = import (../../projects + "/${projectName}") { inherit pkgs lib; };
  }) cfg.projects);
  
  # Collect all packages from enabled projects
  projectPackages = lib.flatten (lib.mapAttrsToList (_: project: project.packages or []) enabledProjects);
  
  # Generate activation scripts for enabled projects
  projectSetupScript = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: project: 
    lib.optionalString (project.repo != null) ''
      # Setup ${name}
      PROJECT_DIR="${homeDir}/dev/${name}"
      
      # Create project directory if it doesn't exist
      if [ ! -d "$PROJECT_DIR" ]; then
        echo "Creating project directory for ${name}..."
        mkdir -p "$PROJECT_DIR"
      fi
      
      # Copy development configuration files directly to project root
      cp ${../../projects}/${name}/.envrc "$PROJECT_DIR/" 2>/dev/null || echo "Warning: .envrc not found for ${name}"
      cp ${../../projects}/${name}/startup.nu "$PROJECT_DIR/" 2>/dev/null || echo "Warning: startup.nu not found for ${name}"
      cp ${../../projects}/${name}/flake.nix "$PROJECT_DIR/" 2>/dev/null || echo "Warning: flake.nix not found for ${name}"
      
      # Set executable permissions on startup script
      chmod +x "$PROJECT_DIR/startup.nu" 2>/dev/null || true
      chown -R ${username}:${if pkgs.stdenv.isDarwin then "staff" else "users"} "$PROJECT_DIR"
    ''
  ) enabledProjects);

in {
  options.development = {
    enable = lib.mkEnableOption "development environment";
    
    projects = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of development projects to enable";
      example = [ "jimmyff-website" "rocket-kit" ];
    };
  };

  config = lib.mkIf cfg.enable {
    # Core development tools + project-specific packages
    environment.systemPackages = with pkgs; [
      # Core development tools
      git
      gh
      direnv
      nix-direnv
      
      # Development utilities
      curl
      wget
      jq
      tree
      
      # Project setup helper
      devSetupScript
    ] ++ projectPackages;

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

    # System activation script for project setup
    system.activationScripts.devProjectSetup = lib.mkIf (cfg.projects != []) {
      text = ''
        echo "Setting up development environment..."
        echo "Enabled projects: ${lib.concatStringsSep ", " cfg.projects}"
        
        # Create dev directory structure
        mkdir -p ${homeDir}/dev
        chown ${username}:${if pkgs.stdenv.isDarwin then "staff" else "users"} ${homeDir}/dev
        
        # Setup projects
        ${projectSetupScript}
        
        echo "Development environment setup complete!"
      '';
      deps = [ "users" ];
    };
  };
}