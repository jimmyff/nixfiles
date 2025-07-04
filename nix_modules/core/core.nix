{ pkgs, ... }:
{

  nix.enable = true;
  nix.package = pkgs.nix;
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Timezone
  time.timeZone = "Europe/London";

  # Touchpad support
  services.libinput = {
    enable = true;
    mouse.naturalScrolling = true;
    touchpad.naturalScrolling = true;  
  };


}