{pkgs-desktop, lib, ... }: {

  imports = [

    ./sway/sway.nix
    ./waybar/waybar.nix

    ./rofi/rofi.nix
    ./tofi/tofi.nix
  ];

  # Desktop
  sway_module.enable = lib.mkDefault true;
  waybar_module.enable = lib.mkDefault true;

  # Launchers
  rofi_module.enable = lib.mkDefault false;
  tofi_module.enable = lib.mkDefault true;


  # Cursor
  home.pointerCursor = {
    package = pkgs-desktop.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 22;
    gtk.enable = true;
  };


home.packages = [

    #pkgs-desktop.fuzzel		                  # launcher (niri)
    #pkgs-desktop.wofi                         # launcher (sway)
    pkgs-desktop.mako				                  # notifications
    pkgs-desktop.wl-clipboard                 # clipboard
    #pkgs-desktop.nautilus			              # file manager
    #pkgs-desktop.font-awesome		            # font icons
    #pkgs-desktop.nerd-fonts.jetbrains-mono   # font
    pkgs-desktop.slurp                        # screenshots
    pkgs-desktop.grim                         # screenshots

    pkgs-desktop.bemoji
    pkgs-desktop.playerctl
    pkgs-desktop.wl-clipboard
    pkgs-desktop.wdisplays

  ];



}