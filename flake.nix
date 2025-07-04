{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:catppuccin/nix";

    # macOS
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { 
    self, 
    nixpkgs, 
    nix-darwin, 
    home-manager, 
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
        specialArgs = { inherit inputs username; };
        modules = [

          # might not be needed
          inputs.home-manager.nixosModules.home-manager

          inputs.catppuccin.nixosModules.catppuccin

          ../hosts/nixelbook/configuration.nix
          ./nix_modules/core/_bundle.nix
          ./nix_modules/desktop/_bundle.nix
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
