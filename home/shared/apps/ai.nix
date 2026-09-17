{
  pkgs,
  pkgs-ai,
  pkgs-dev-tools,
  lib,
  config,
  osConfig,
  ...
}: let
  claude-cfg = config.claude-code_module;
  antigravity-cfg = config.antigravity-cli_module;
  codex-cfg = config.codex_module;
  pi-cfg = config.pi_module;

  aiSkills = "${config.home.homeDirectory}/nixfiles/dotfiles/ai/skills";
  aiAgentsMd = "${config.home.homeDirectory}/nixfiles/dotfiles/ai/AGENTS.md";

  # Per-host agent notes, imported by AGENTS.md: system facts only, never project details.
  hostName = osConfig.networking.hostName;
  hostNotes = "${config.home.homeDirectory}/nixfiles/hosts/${hostName}/HOST.md";

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
  options.codex_module.enable = lib.mkEnableOption "OpenAI Codex CLI";
  options.pi_module.enable = lib.mkEnableOption "Pi coding agent";

  config = lib.mkMerge [
    # docket backs the project-docs skill. Every harness below links the shared
    # skills directory, so docket is gated on any of them rather than on one.
    (lib.mkIf (claude-cfg.enable || antigravity-cfg.enable || codex-cfg.enable || pi-cfg.enable) {
      home.packages = [docket];
      assertions = [
        {
          assertion = builtins.pathExists (../../../hosts + "/${hostName}/HOST.md");
          message = "hosts/${hostName}/HOST.md is missing — every host carries agent notes";
        }
      ];
      home.file.".agents/HOST.md".source = config.lib.file.mkOutOfStoreSymlink hostNotes;
    })

    # ~/.agents/skills is the Agent Skills standard root. Codex and Pi both
    # discover it and both follow symlinks through to the real directory, so one
    # link serves both. Claude reads ~/.claude/skills instead (below).
    (lib.mkIf (codex-cfg.enable || pi-cfg.enable) {
      home.file.".agents/skills".source = config.lib.file.mkOutOfStoreSymlink aiSkills;
    })

    (lib.mkIf claude-cfg.enable {
      programs.claude-code = {
        enable = true;
        package = pkgs-ai.claude-code;
      };
      home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        pkgs.bubblewrap
        pkgs.socat
      ];
      home.file.".claude/statusline.sh".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/claude/statusline.sh";
      home.file.".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink aiAgentsMd;
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
      home.file.".gemini/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink aiAgentsMd;
      home.file.".gemini/skills".source = config.lib.file.mkOutOfStoreSymlink aiSkills;
    })
    (lib.mkIf codex-cfg.enable {
      home.packages = [pkgs-ai.codex];
      home.file.".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink aiAgentsMd;

      # Codex writes back to config.toml (model selection, [projects] trust levels,
      # notice-dismissal flags), so it hits exactly the EROFS trap described above
      # for Claude's settings.json — its atomic write resolves the symlink and drops
      # a temp file beside the target. A direct symlink lands that temp file in
      # dotfiles/codex/, which is writable.
      home.activation.codexWritableConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p "${config.home.homeDirectory}/.codex"
        run ln -sfn "${config.home.homeDirectory}/nixfiles/dotfiles/codex/config.toml" "${config.home.homeDirectory}/.codex/config.toml"
      '';
    })
    (lib.mkIf pi-cfg.enable {
      home.packages = [pkgs-ai.pi-coding-agent];
      home.file.".pi/agent/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink aiAgentsMd;

      # Pi rewrites settings.json from its /settings command — same reasoning as
      # the Codex and Claude config files above.
      home.activation.piWritableSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p "${config.home.homeDirectory}/.pi/agent"
        run ln -sfn "${config.home.homeDirectory}/nixfiles/dotfiles/pi/settings.json" "${config.home.homeDirectory}/.pi/agent/settings.json"
      '';
    })
  ];
}
