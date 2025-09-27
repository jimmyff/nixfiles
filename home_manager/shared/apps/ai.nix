{ pkgs, lib, config, ... }: {

  programs.claude-code.enable = true;
  programs.gemini-cli.enable = true;

  home.file.".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/settings.json";
  home.file.".claude/statusline.sh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/statusline.sh";
  home.file.".gemini/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/gemini/settings.json";

}
