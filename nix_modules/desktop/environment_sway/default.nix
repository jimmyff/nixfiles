{pkgs, lib, ... }: {

  imports = [
    ./greeter/greetd.nix
    ./sway.nix
    ./thunar.nix
  ];

  # Power management
  powerManagement.enable = true;
  services.tlp.enable = true;

  sway_module.enable = lib.mkDefault true;
}
