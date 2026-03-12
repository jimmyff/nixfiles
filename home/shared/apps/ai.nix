{ pkgs-ai, lib, config, ... }:
let
  claude-cfg = config.claude-code_module;
  gemini-cfg = config.gemini-cli_module;
in {
  options.claude-code_module.enable = lib.mkEnableOption "Claude Code" // { default = true; };
  options.gemini-cli_module.enable = lib.mkEnableOption "Gemini CLI";

  config = lib.mkMerge [
    (lib.mkIf claude-cfg.enable {
      programs.claude-code = {
        enable = true;
        package = pkgs-ai.claude-code;
      };
      home.packages = [ pkgs-ai.claude-monitor ];
      home.file.".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/settings.json";
      home.file.".claude/statusline.sh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/statusline.sh";
      home.file.".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/AGENTS.md";
      home.file.".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/skills";
    })
    (lib.mkIf gemini-cfg.enable {
      programs.gemini-cli = {
        enable = true;
        package = pkgs-ai.gemini-cli;
      };
      home.file.".gemini/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/gemini/settings.json";
      home.file.".gemini/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/AGENTS.md";
    })
  ];
}
