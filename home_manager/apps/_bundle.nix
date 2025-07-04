{pkgs, lib, ... }: {

  imports = [

    ./kitty/kitty.nix
    ./ghostty/ghostty.nix

  ];


  # Terminals
  kitty_module.enable = lib.mkDefault true;
  ghostty_module.enable = lib.mkDefault false;

}