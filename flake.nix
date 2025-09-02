{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # macOS
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nixvim.url = "github:nix-community/nixvim";


    # nvf - for neovim
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
  
  };

  outputs = inputs @ { 
    self, 
    nixpkgs, 
    nix-darwin, 
    home-manager,
    nixos-hardware,
    agenix,
    nixvim,
    nvf,
    ... 
  } : let 
    username = "jimmyff";
    specialArgs = { inherit inputs username; pkgs-unstable = nixpkgs.legacyPackages; };
  in
  {

    # Nixos configurations
    nixosConfigurations = {

      # Jimmy's Pixelbook
      nixelbook = nixpkgs.lib.nixosSystem {
        inherit specialArgs;

        modules = [


          # add from this list: https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
          nixos-hardware.nixosModules.google-pixelbook

          ./hosts/nixelbook/configuration.nix

          ./nix_modules/core/linux
          ./nix_modules/desktop/linux

          agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = specialArgs;
            home-manager.users.${username} = import ./home_manager/linux;
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
        ./nix_modules/core/darwin

        agenix.nixosModules.default
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = specialArgs;
          home-manager.users.${username} = import ./home_manager/darwin;
        }
      ];

    };
    
  };
}
