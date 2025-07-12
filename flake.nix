{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:catppuccin/nix";

    # macOS
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # nvf - for neovim
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # agenix (encryption)
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = inputs @ { 
    self, 
    nixpkgs, 
    nix-darwin, 
    home-manager,
    nixos-hardware,
    agenix,
    ... 
  } : let 
    username = "jimmyff";
    specialArgs = { inherit inputs username; };
  in
  {

    # Nixos configurations
    nixosConfigurations = {

      # Jimmy's Pixelbook
      nixelbook = nixpkgs.lib.nixosSystem {
        inherit specialArgs;

        modules = [

          inputs.catppuccin.nixosModules.catppuccin

          # add from this list: https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
          nixos-hardware.nixosModules.google-pixelbook

          ./hosts/nixelbook/configuration.nix

          ./nix_modules/core/_bundle.nix
          ./nix_modules/desktop/_bundle.nix

          agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = specialArgs;
            home-manager.users.${username} = import ./home_manager/home.nix;
          }
        ];
      };
      homeManagerModules.default = ./home;
    };

    # MacOS configurations
    darwinConfigurations.jimmyff-mbp14 = nix-darwin.lib.darwinSystem {
      inherit specialArgs;

      system = "aarch64-darwin";
      modules = [ 
        ./hosts/jimmyff-mpb14/configuration.nix
        ./nix_modules/core/_bundle_darwin.nix

        agenix.nixosModules.default
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = specialArgs;
          home-manager.users.${username} = import ./home_manager/home_darwin.nix;
        }
      ];

    };
    
  };
}
