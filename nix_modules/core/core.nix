{ pkgs, ... }:
{

  nix.enable = true;
  nix.package = pkgs.nix;
  nixpkgs.config.allowUnfree = true; 

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Timezone
  time.timeZone = "Europe/London";

  # Touchpad support
  services.libinput = {
    enable = true;
    mouse.naturalScrolling = true;
    touchpad.naturalScrolling = true;  
  };


  environment.systemPackages = [
    pkgs.age                      # Encryption library  
    pkgs.agenix-cli               # Age nix tool
  ];


}