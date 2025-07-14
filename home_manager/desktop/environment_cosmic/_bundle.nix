{pkgs, lib, ... }: {

  # imports = [  ];

  # Cursor
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 22;
    gtk.enable = true;
  };

  # home.packages = [
  # ];

  # Cosmic config
  home.file.".config/cosmic".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/cosmic/.config/cosmic";

}