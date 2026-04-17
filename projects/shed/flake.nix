{
  description = "Tinkering Space for Shed - Utilities, mini projects, and tools";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = {
    self,
    nixpkgs-stable,
  }: let
    utils = import ./devshell-utils.nix;
  in {
    devShells = utils.eachSystem (system: let
      pkgs-stable = nixpkgs-stable.legacyPackages.${system};
    in
      pkgs-stable.mkShellNoCC {
        buildInputs = with pkgs-stable; [
        ];

        shellHook = ''
          ${utils.darwinPathHook pkgs-stable}
          echo "🏚️ Entering Shed tinkering space"
          echo ""
          ${utils.commonShellHook}
        '';
      });
  };
}
