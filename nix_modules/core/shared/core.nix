{ pkgs-stable, pkgs-dev-tools, inputs, ... }:
{

  nix.enable = true;
  nix.package = pkgs-stable.nix;
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Timezone
  time.timeZone = "Europe/London";


  environment.systemPackages = [
    pkgs-stable.age                                        # Encryption library
    inputs.agenix.packages.${pkgs-stable.system}.default  # Age nix secrets tool
    pkgs-stable.bat                      # Cat clone with syntax highlighting
    pkgs-stable.minisign                  # Release signing tool
    pkgs-stable.vim                      # Vi/Vim text editor
  ];

  environment.shells = [ pkgs-stable.bash pkgs-stable.zsh pkgs-dev-tools.nushell ];

}