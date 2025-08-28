{pkgs, lib, ... }: {

  imports = [

    ./neovim/neovim.nix
    ./kitty/kitty.nix
    ./ghostty/ghostty.nix
    ./chromium/chromium.nix
    ./vscode/vscode.nix
    ./nu/nu.nix

  ];

  # apps
  chromium_module.enable = lib.mkDefault true;

  # editors
  vscode_module.enable = lib.mkDefault true;
  neovim_module.enable = lib.mkDefault true;

  # Terminals
  kitty_module.enable = lib.mkDefault true;
  ghostty_module.enable = lib.mkDefault false;


  home.packages = [
    # pkgs.vim
    pkgs.wget
    pkgs.neofetch
  ];

  # TODO: Move this
  programs.git = {
      enable = true;
      userName = "jimmyff";
      userEmail = "code@rocketware.co.uk";
  };

  # btop
  programs.btop = {
    enable = true;
    settings = {
      #color_theme = "HotPurpleTrafficLight";
      vim_keys = true;
    };
  };

}