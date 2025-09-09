{pkgs, lib, ... }: {

  imports = [

    ./helix/helix.nix
    ./kitty/kitty.nix
    ./ghostty/ghostty.nix
    ./rio/rio.nix
    ./alacritty/alacritty.nix
    ./zellij/zellij.nix
    ./chromium/chromium.nix
    ./vscode/vscode.nix
    ./zed/zed.nix
    ./nu/nu.nix
    ./yazi/yazi.nix
    ./ai.nix
    
    # Import services
    ../services/git.nix
    ../services/ssh.nix
  ];

  # apps
  chromium_module.enable = lib.mkDefault true;
  yazi_module.enable = lib.mkDefault true;

  # editors
  vscode_module.enable = lib.mkDefault true;
  helix_module.enable = lib.mkDefault true;
  zed_module.enable = lib.mkDefault true;

  # Terminals
  kitty_module.enable = lib.mkDefault true;
  ghostty_module.enable = lib.mkDefault false;
  rio_module.enable = lib.mkDefault true;
  alacritty_module.enable = lib.mkDefault true;
  zellij_module.enable = lib.mkDefault true;

  # Default terminal
  home.sessionVariables.TERMINAL = lib.mkDefault "kitty";

  # programs
  git_module.enable = lib.mkDefault true;


  home.packages = [
    pkgs.wget
    pkgs.neofetch
  ];

  # btop
  programs.btop = {
    enable = true;
    settings = {
      #color_theme = "HotPurpleTrafficLight";
      vim_keys = true;
    };
  };

  # ripgrep - required for nvim telescope
  programs.ripgrep.enable = true;


}
