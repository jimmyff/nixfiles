{
  pkgs-ai,
  lib,
  config,
  ...
}: let
  claude-cfg = config.claude-code_module;
  antigravity-cfg = config.antigravity-cli_module;
in {
  options.claude-code_module.enable = lib.mkEnableOption "Claude Code";
  options.antigravity-cli_module.enable = lib.mkEnableOption "Antigravity CLI";

  config = lib.mkMerge [
    (lib.mkIf claude-cfg.enable {
      programs.claude-code = {
        enable = true;
        package = pkgs-ai.claude-code;
      };
      home.packages = [];
      home.file.".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/settings.json";
      home.file.".claude/statusline.sh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/statusline.sh";
      home.file.".claude/keybindings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/keybindings.json";
      home.file.".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/AGENTS.md";
      home.file.".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/skills";
    })
    (lib.mkIf antigravity-cfg.enable {
      home.packages = [pkgs-ai.antigravity-cli];
      home.file.".gemini/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/antigravity/settings.json";
      home.file.".gemini/mcp_config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/antigravity/mcp_config.json";
      home.file.".gemini/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/AGENTS.md";
      home.file.".gemini/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/skills";
    })
  ];
}
