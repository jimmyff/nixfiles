{ pkgs-stable, ... }:
{

  nix.enable = true;
  nix.package = pkgs-stable.nix;
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Timezone
  time.timeZone = "Europe/London";


  environment.systemPackages = [
    pkgs-stable.age                      # Encryption library
    pkgs-stable.agenix-cli               # Age nix tool
    pkgs-stable.bat                      # Cat clone with syntax highlighting
  ];

  environment.shells = with pkgs-stable; [ bash zsh nushell ];

}