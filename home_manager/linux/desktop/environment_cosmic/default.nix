{pkgs, lib, config, ... }: {

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

  # Cosmic config is now handled by shared/dotfiles.nix

}