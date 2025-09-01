{ pkgs, ... }:
{

  nix.enable = true;
  nix.package = pkgs.nix;
  nixpkgs.config.allowUnfree = true; 

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Timezone
  time.timeZone = "Europe/London";


  environment.systemPackages = [
    pkgs.age                      # Encryption library  
    pkgs.agenix-cli               # Age nix tool
  ];

  environment.shells = with pkgs; [ nushell ];

}