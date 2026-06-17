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

    # zellij-attention: background plugin that flags which tab needs attention with a
    # 3-state priority indicator — attention/working/done (jimmyff's fork of
    # KiryuuLight/zellij-attention: https://github.com/jimmyff/zellij-attention).
    # Driven by `zellij pipe` from Claude Code hooks (see dotfiles/claude/settings.json).
    home.file.".local/share/zellij/plugins/zellij-attention.wasm".source = pkgs-apps.fetchurl {
      url = "https://github.com/jimmyff/zellij-attention/releases/download/v0.4.0/zellij-attention.wasm";
      hash = "sha256-cdVp+Lsde1S2NsY3pygM4BVc8uz5XHBFlo7gwMw2gIQ=";
    };
  };
}