{pkgs, lib, ... }: {

  imports = [
    ./desktop_system.nix
    ./greeter/greetd.nix
    ./sound.nix
    ./power.nix
    ./sway.nix
  ];

  sway_module.enable = lib.mkDefault true;
}
