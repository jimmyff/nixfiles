{
  pkgs-apps,
  lib,
  config,
  ...
}: {
  options = {
    zellij_module.enable = lib.mkEnableOption "enables zellij_module";
  };

  config = lib.mkIf config.zellij_module.enable {
    programs.zellij = {
      enable = true;
    };
    home.file.".config/zellij".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixfiles/dotfiles/zellij";

    # room: floating tab switcher (https://github.com/rvcas/room).
    # Pinned wasm fetched into the store; config.kdl references it via
    # file:~/.local/share/zellij/plugins/room.wasm (zellij shell-expands ~).
    # Kept out of ~/.config/zellij since that dir is a single out-of-store symlink.
    home.file.".local/share/zellij/plugins/room.wasm".source = pkgs-apps.fetchurl {
      url = "https://github.com/rvcas/room/releases/download/v1.2.1/room.wasm";
      hash = "sha256-kLSDpAt2JGj7dYYhYFh6BfvtzVwTrcs+0jHwG/nActE=";
    };

    # zellij-attention: background plugin that flags tabs needing attention
    # (https://github.com/KiryuuLight/zellij-attention). Driven by `zellij pipe`
    # from Claude Code's Notification hook (see dotfiles/claude/settings.json).
    home.file.".local/share/zellij/plugins/zellij-attention.wasm".source = pkgs-apps.fetchurl {
      url = "https://github.com/KiryuuLight/zellij-attention/releases/download/v0.3.1/zellij-attention.wasm";
      hash = "sha256-QgkzerYacxRI7HMzYvPvaZqQW7tcARKpOm1hY2D9ci8=";
    };
  };
}