{pkgs, lib, ... }: {

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
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 22;
    gtk.enable = true;
  };


home.packages = [

    #pkgs.fuzzel		                  # launcher (niri)
    #pkgs.wofi                         # launcher (sway)
    pkgs.mako				                  # notifications
    pkgs.wl-clipboard                 # clipboard
    #pkgs.nautilus			              # file manager
    #pkgs.font-awesome		            # font icons
    #pkgs.nerd-fonts.jetbrains-mono   # font
    pkgs.slurp                        # screenshots
    pkgs.grim                         # screenshots

    pkgs.bemoji
    pkgs.playerctl
    pkgs.wl-clipboard
    pkgs.wdisplays

  ];



}