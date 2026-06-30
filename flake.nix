{
  description = "Nixos config flake";

  inputs = {
    # Specialized nixpkgs inputs for different update cadences
    pkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";           # Core system, stable packages
    pkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";      # Desktop, apps, dev tools
    pkgs-ai.url = "github:nixos/nixpkgs/nixpkgs-unstable";          # AI tools, bleeding edge

    # Kanata pinned to a fixed nixpkgs rev so its binary's cdhash never changes —
    # macOS binds the Input Monitoring (TCC) grant to that cdhash, so freezing the
    # build keeps home-row mods working across rebuilds and `nix flake update`.
    # To bump kanata: change this rev, then re-grant Input Monitoring once (see docs).
    nixpkgs-kanata.url = "github:nixos/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";

    # macOS (nix-darwin-25.11 matches pkgs-stable/home-manager)
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "pkgs-stable";



    # nvf - for neovim
    # Disabled as nvim not in use
    # nvf = {
    #   url = "github:notashelf/nvf";
    #   inputs.nixpkgs.follows = "pkgs-stable";
    # };

    # home-manager (release-25.11 matches nixos-25.11)
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "pkgs-stable";
    };

    # nix hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # agenix (encryption)
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "pkgs-stable";
    };

    # NUR (Nix User Repository) - required if using librewolf
    # nur = {
    #   url = "github:nix-community/NUR";
    #   inputs.nixpkgs.follows = "pkgs-stable";
    # };

    # Private vault repository for encrypted secrets
    nixfiles-vault = {
      url = "git+ssh://git@github.com/jimmyff/nixfiles_vault.git";
      flake = false;
    };

    # Android SDK packages
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "pkgs-stable";
    };

    # herdr — agent-aware terminal multiplexer (mux's trial default backend, alongside zellij).
    # Standalone Rust binary with a vendored zig VT lib; it pins its own toolchain, so no `follows`.
    herdr.url = "github:ogulcancelik/herdr";

  };

  outputs = inputs @ {
    self,
    pkgs-stable,
    pkgs-unstable,
    pkgs-ai,
    nixpkgs-kanata,
    nix-darwin,
    home-manager,
    nixos-hardware,
    agenix,
    # nur, # required if using librewolf
    nixfiles-vault,
    android-nixpkgs,
    # nvf,
    ...
  } : let
    username = "jimmyff";

    # Helper to create specialized packages for a system
    mkSpecialArgs = system: let
      unstable = import pkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      inherit inputs username nixfiles-vault self;
      pkgs-stable = import pkgs-stable {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-desktop = unstable;
      pkgs-apps = unstable;
      pkgs-dev-tools = unstable;
      pkgs-dev-flutter = unstable;
      pkgs-dev-rust = unstable;
      pkgs-dev-android = unstable;
      pkgs-ai = import pkgs-ai {
        inherit system;
        config.allowUnfree = true;
      };
      # Pinned solely for kanata (darwin); see the nixpkgs-kanata input above.
      pkgs-kanata = import nixpkgs-kanata {
        inherit system;
        config.allowUnfree = true;
      };
      # herdr multiplexer — prebuilt from its own flake (its own pinned toolchain).
      pkgs-herdr = inputs.herdr.packages.${system}.default;
    };

    # Define once per system
    linuxArgs = mkSpecialArgs "x86_64-linux";
    darwinArgs = mkSpecialArgs "aarch64-darwin";
  in
  {

    # Library functions (consumed by project flakes)
    lib = {
      mkKiln = import ./modules/kiln/lib.nix { inherit inputs; };
    };

    # Nixos configurations
    nixosConfigurations = {

      # Jimmy's Pixelbook
      nixelbook = pkgs-stable.lib.nixosSystem {
        specialArgs = linuxArgs;

        modules = [
          # NOTE: Removed nixos-hardware.nixosModules.google-pixelbook due to conflicts
          # The google-pixelbook module sets i915 kernel params that break suspend/resume
          # We use custom pixelbook-go config instead (imported in configuration.nix)

          ./hosts/nixelbook/configuration.nix

          ./modules/core/linux
          ./modules/workstation
          ./modules/workstation/desktop/linux

          agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = linuxArgs;
            home-manager.users.${username} = { ... }: {
              imports = [ ./home/linux ];
              desktop.enable = true;
              claude-code_module.enable = true;
            };
          }
        ];
      };

      # Jimmy's Proxmox build server (headless)
      nixbox = pkgs-stable.lib.nixosSystem {
        specialArgs = linuxArgs;

        modules = [
          ./hosts/nixbox/configuration.nix

          ./modules/core/linux

          agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = linuxArgs;
            home-manager.users.${username} = { ... }: {
              imports = [ ./home/linux ];
              claude-code_module.enable = true;
            };
          }
        ];
      };

      # Jimmy's Proxmox NAS & media server (headless)
      nasbox = pkgs-stable.lib.nixosSystem {
        specialArgs = linuxArgs;

        modules = [
          ./hosts/nasbox/configuration.nix

          ./modules/core/linux

          agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = linuxArgs;
            home-manager.users.${username} = { ... }: {
              imports = [ ./home/linux ];
              claude-code_module.enable = true;
            };
          }
        ];
      };

      # Rocketware self-hosted ntfy push host (GCE e2-micro) — first cloud host; deployed from nixbox
      gcp-beacon = pkgs-stable.lib.nixosSystem {
        specialArgs = linuxArgs;

        modules = [
          ./hosts/gcp-beacon/configuration.nix

          ./modules/core/linux

          agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = linuxArgs;
            home-manager.users.${username} = { ... }: {
              imports = [ ./home/linux ]; # desktop.enable + claude-code default off
            };
          }
        ];
      };
    };

    # MacOS configurations
    darwinConfigurations.jimmyff-mbp14 = nix-darwin.lib.darwinSystem {
      specialArgs = darwinArgs;

      modules = [
        ./hosts/jimmyff-mbp14/configuration.nix
        ./modules/core/darwin
        ./modules/workstation

        agenix.darwinModules.default
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = darwinArgs;
          home-manager.users.${username} = { ... }: {
            imports = [ ./home/darwin ];
            claude-code_module.enable = true;
          };
        }
      ];

    };
    
  };
}
