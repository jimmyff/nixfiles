{pkgs, lib, ... }: {

  imports = [

    ./kitty/kitty.nix
    ./ghostty/ghostty.nix
    ./chromium/chromium.nix
    ./vscode/vscode.nix

  ];

  # apps
  chromium_module.enable = lib.mkDefault true;
  vscode_module.enable = lib.mkDefault true;

  # Terminals
  kitty_module.enable = lib.mkDefault true;
  ghostty_module.enable = lib.mkDefault false;


  home.packages = [
    pkgs.neofetch                     # info
  ];

}