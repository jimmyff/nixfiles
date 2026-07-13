{
  pkgs,
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
      home.packages = lib.optionals pkgs.stdenv.isLinux [
        pkgs.bubblewrap
        pkgs.socat
      ];
      home.file.".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/settings.json";
      home.file.".claude/statusline.sh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/statusline.sh";
      home.file.".claude/keybindings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/keybindings.json";
      home.file.".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/AGENTS.md";
      home.file.".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/skills";

      # Canonical Claude Code MCP config (dotfiles/ai/mcp.json), symlinked into
      # every project checkout. New worktrees are seeded by the glittering
      # global worktree hook; existing checkouts by projectMcpSymlinks below.
      xdg.configFile."glittering/hooks/worktree/on-add".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/glittering/worktree-on-add";

      home.activation.projectMcpSymlinks = lib.hm.dag.entryAfter ["writeBoundary"] ''
        canonical="${config.home.homeDirectory}/nixfiles/dotfiles/ai/mcp.json"
        projects="${config.home.homeDirectory}/projects"
        if [ -d "$projects" ]; then
          for dir in "$projects"/*/*/; do
            # $dir keeps its trailing slash; skips the unmatched-glob literal too
            [ -e "$dir.git" ] || continue
            if [ "$(readlink "$dir.mcp.json" 2>/dev/null || true)" != "$canonical" ]; then
              run ln -sfn "$canonical" "$dir.mcp.json"
            fi
          done
        fi
      '';
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
