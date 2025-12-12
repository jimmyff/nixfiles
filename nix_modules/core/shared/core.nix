{ pkgs-stable, inputs, ... }:
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
    pkgs-stable.vim                      # Vi/Vim text editor
  ];

  environment.shells = with pkgs-stable; [ bash zsh nushell ];

}