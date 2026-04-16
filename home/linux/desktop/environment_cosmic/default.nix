{pkgs-desktop, lib, config, ... }: {
  options.cosmic_module.enable = lib.mkEnableOption "COSMIC desktop configuration";

  config = lib.mkIf config.cosmic_module.enable {
    # Cursor
    home.pointerCursor = {
      package = pkgs-desktop.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 22;
      gtk.enable = true;
    };

    home.file.".config/cosmic".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixfiles/dotfiles/cosmic";
  };
}
