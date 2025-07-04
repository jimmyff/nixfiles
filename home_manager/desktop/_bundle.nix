{pkgs, lib, ... }: {

  imports = [

    ./sway/sway.nix
    ./waybar/waybar.nix
    ./tofi/tofi.nix
  ];

  # Desktop
  sway_module.enable = lib.mkDefault true;
  waybar_module.enable = lib.mkDefault true;
  tofi_module.enable = lib.mkDefault false;

}