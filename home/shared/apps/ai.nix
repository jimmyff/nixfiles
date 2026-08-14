{
  pkgs,
  pkgs-ai,
  pkgs-dev-tools,
  lib,
  config,
  ...
}: let
  claude-cfg = config.claude-code_module;
  antigravity-cfg = config.antigravity-cli_module;

  aiSkills = "${config.home.homeDirectory}/nixfiles/dotfiles/ai/skills";

  # The project-docs helper on PATH. It runs from the live dotfiles path rather than a store copy:
  # the skill is edited most sessions, and `$env.FILE_PWD` does not resolve symlinks, so the script
  # must be invoked where its own templates/ sits beside it.
  #
  # DOCKET_STDOUT is the half of "is a person driving this" that nushell cannot see for itself —
  # it replaces stdout in script mode, so `is-terminal --stdout` is false even on a real pty.
  # A shell can tell, so it answers here; see `tty-driven` in docs.nu.
  docket = pkgs.writeShellScriptBin "docket" ''
    if [ -t 1 ]; then export DOCKET_STDOUT=1; else export DOCKET_STDOUT=0; fi
    exec ${pkgs-dev-tools.nushell}/bin/nu "${aiSkills}/project-docs/scripts/docs.nu" "$@"
  '';
in {
  options.claude-code_module.enable = lib.mkEnableOption "Claude Code";
  options.antigravity-cli_module.enable = lib.mkEnableOption "Antigravity CLI";

  config = lib.mkMerge [
    (lib.mkIf claude-cfg.enable {
      programs.claude-code = {
        enable = true;
        package = pkgs-ai.claude-code;
      };
      home.packages =
        [docket]
        ++ lib.optionals pkgs.stdenv.isLinux [
          pkgs.bubblewrap
          pkgs.socat
        ];
      home.file.".claude/statusline.sh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/statusline.sh";
      home.file.".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/ai/AGENTS.md";
      home.file.".claude/skills".source = config.lib.file.mkOutOfStoreSymlink aiSkills;

      # settings.json and keybindings.json are the two files Claude Code writes back to
      # itself (/effort, /keybindings), so they cannot go through home.file: its
      # mkOutOfStoreSymlink is a two-hop link, and Claude's atomic write resolves only the
      # first hop before dropping its temp file beside the result — inside /nix/store, so
      # the write dies with EROFS. A direct symlink puts that temp file in dotfiles/claude/,
      # which is writable. The claude-settings clean filter (.gitattributes) then keeps the
      # resulting effortLevel churn out of commits.
      home.activation.claudeWritableDotfiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p "${config.home.homeDirectory}/.claude"
        for f in settings.json keybindings.json; do
          run ln -sfn "${config.home.homeDirectory}/nixfiles/dotfiles/claude/$f" "${config.home.homeDirectory}/.claude/$f"
        done
      '';

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
      home.file.".gemini/skills".source = config.lib.file.mkOutOfStoreSymlink aiSkills;
    })
  ];
}
