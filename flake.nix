{
  description = "Nixos config flake";

  inputs = {
    # Default nixpkgs - will be removed once migration to specialized inputs is complete
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Specialized nixpkgs inputs for different update cadences
    pkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";           # Core system, rarely changes
    pkgs-desktop.url = "github:nixos/nixpkgs/nixos-unstable";       # Desktop environments
    pkgs-apps.url = "github:nixos/nixpkgs/nixos-unstable";          # User applications
    pkgs-ai.url = "github:nixos/nixpkgs/nixpkgs-unstable";          # AI tools, bleeding edge
    pkgs-dev-tools.url = "github:nixos/nixpkgs/nixos-unstable";     # Dev tools (editors, LSPs, formatters)
    pkgs-dev-flutter.url = "github:nixos/nixpkgs/nixos-unstable";   # Flutter/Dart development
    pkgs-dev-rust.url = "github:nixos/nixpkgs/nixos-unstable";      # Rust development
    pkgs-dev-android.url = "github:nixos/nixpkgs/nixos-unstable";   # Android development

    # macOS
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";



    # nvf - for neovim
    # Disabled as nvim not in use
    # nvf = {
    #   url = "github:notashelf/nvf";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # home-manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # agenix (encryption)
    # TODO: not using it yet
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NUR (Nix User Repository) - for Firefox extensions
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Private vault repository for encrypted secrets
    nixfiles-vault = {
      url = "git+ssh://git@github.com/jimmyff/nixfiles_vault.git";
      flake = false;
    };

    # Android SDK packages
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    pkgs-stable,
    pkgs-desktop,
    pkgs-apps,
    pkgs-ai,
    pkgs-dev-tools,
    pkgs-dev-flutter,
    pkgs-dev-rust,
    pkgs-dev-android,
    nix-darwin,
    home-manager,
    nixos-hardware,
    agenix,
    nur,
    nixfiles-vault,
    android-nixpkgs,
    # nvf,
    ...
  } : let
    username = "jimmyff";

    # Helper to create specialized packages for a system
    mkSpecialArgs = system: {
      inherit inputs username nixfiles-vault;
      pkgs-unstable = nixpkgs.legacyPackages.${system};
      pkgs-stable = import pkgs-stable {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-desktop = import pkgs-desktop {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-apps = import pkgs-apps {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-ai = import pkgs-ai {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-dev-tools = import pkgs-dev-tools {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-dev-flutter = import pkgs-dev-flutter {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-dev-rust = import pkgs-dev-rust {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-dev-android = import pkgs-dev-android {
        inherit system;
        config.allowUnfree = true;
      };
    };

    # Define once per system
    linuxArgs = mkSpecialArgs "x86_64-linux";
    darwinArgs = mkSpecialArgs "aarch64-darwin";
  in
  {

    # Nixos configurations
    nixosConfigurations = {

      # Jimmy's Pixelbook
      nixelbook = nixpkgs.lib.nixosSystem {
        specialArgs = linuxArgs;

        modules = [
          # NOTE: Removed nixos-hardware.nixosModules.google-pixelbook due to conflicts
          # The google-pixelbook module sets i915 kernel params that break suspend/resume
          # We use custom pixelbook-go config instead (imported in configuration.nix)

          ./hosts/nixelbook/configuration.nix

          ./nix_modules/core/linux
          ./nix_modules/desktop/linux

          agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = linuxArgs;
            home-manager.users.${username} = import ./home_manager/linux;
          }
        ];
      };
    };

    # MacOS configurations
    darwinConfigurations.jimmyff-mbp14 = nix-darwin.lib.darwinSystem {
      specialArgs = darwinArgs;

      system = "aarch64-darwin";
      modules = [ 
        ./hosts/jimmyff-mpb14/configuration.nix
        ./nix_modules/core/darwin

        agenix.darwinModules.default
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = darwinArgs;
          home-manager.users.${username} = import ./home_manager/darwin;
        }
      ];

    };
    
  };
}
