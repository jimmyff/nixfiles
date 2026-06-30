{
  pkgs-herdr,
  lib,
  config,
  ...
}: {
  options = {
    herdr_module.enable = lib.mkEnableOption "enables herdr_module";
  };

  config = lib.mkIf config.herdr_module.enable {
    home.packages = [ pkgs-herdr ];

    # herdr reads a single TOML file. Out-of-store symlink (like the claude settings) so edits
    # apply on the next herdr start, not darwin-rebuild — handy while trialling keybinds. herdr
    # writes runtime state elsewhere (sockets, cache); `onboarding = false` keeps it from
    # rewriting this file. See dotfiles/herdr/config.toml and docs/multiplexing.md.
    home.file.".config/herdr/config.toml".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixfiles/dotfiles/herdr/config.toml";
  };
}
