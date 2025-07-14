{pkgs, lib, ... }: {

  imports = [
    ./greeter/greetd.nix
    ./sway.nix
    ./power.nix
    ./thunar.nix
  ];

  sway_module.enable = lib.mkDefault true;
}
