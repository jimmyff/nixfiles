{
  lib,
  pkgs,
  config,
  ...
}: let
  # Codex rewrites its own config.toml: `/model` persists model + reasoning effort,
  # dismissed warnings accumulate under [notice], and every folder opened records a
  # [projects."<abs path>"] trust level. Only the first is worth committing.
  #
  # This is deliberately line-based rather than a TOML round-trip (tomlq, dasel):
  # those reserialise and drop comments, and the comments in dotfiles/codex/config.toml
  # carry the sandbox caveats. Dropping a table means skipping until the next header.
  codexConfigClean = pkgs.writeShellScriptBin "codex-config-clean" ''
    exec ${pkgs.gawk}/bin/awk '
      BEGIN { drop = 0; root = 1; blanks = 0 }

      # Table header: decide whether this whole table is machine state.
      /^[[:space:]]*\[/ {
        root = 0
        hdr = $0
        sub(/^[[:space:]]*\[+/, "", hdr)   # strip [ or [[
        sub(/\].*$/, "", hdr)              # strip ] and anything after
        split(hdr, seg, ".")
        first = seg[1]
        gsub(/^"|"$/, "", first)
        drop = (first == "notice" || first == "projects")
      }
      drop { next }

      # Hold blank lines back so a dropped trailing table leaves no gap behind.
      /^[[:space:]]*$/ { blanks++; next }

      {
        while (blanks > 0) { print ""; blanks-- }
        if (root && $0 ~ /^[[:space:]]*model_reasoning_effort[[:space:]]*=/)
          print "model_reasoning_effort = \"high\""
        else
          print
      }
    '
  '';
in {
  options = {
    git_module.enable = lib.mkEnableOption "enables git_module";
  };

  config = lib.mkIf config.git_module.enable {
    programs.git = {
      enable = true;
      lfs.enable = true;
      # Global excludes (~/.config/git/ignore): machine-managed files that live
      # in every checkout but never belong in a repo.
      ignores = [
        ".mcp.json"
        ".glittering/"
        "**/.claude/settings.local.json"
      ];
      settings = {
        user = {
          name = "jimmyff";
          email = "code@rocketware.co.uk";
        };
        # `git sdiff` for on-demand side-by-side view
        alias.sdiff = "!git -c delta.side-by-side=true diff";
        # Keep agent-authored churn out of commits (see .gitattributes).
        # Pin effortLevel in Claude's settings.json.
        filter.claude-settings.clean = "jq --indent 2 '.effortLevel = \"xhigh\"'";
        # Drop Pi's install state: lastChangelogVersion is regenerated, and
        # trackingId is a per-install analytics identifier.
        filter.pi-settings.clean = "jq --indent 2 'del(.lastChangelogVersion, .trackingId)'";
        # Strip Codex's [notice]/[projects] tables and pin its reasoning effort.
        filter.codex-config.clean = lib.getExe codexConfigClean;
      };
    };

    # Diff pager (wired into git via enableGitIntegration)
    programs.delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        line-numbers = true;
        navigate = true; # n/N to move between diff sections
        syntax-theme = "gruvbox-dark";
      };
    };

    # Github cli
    programs.gh = {
      enable = true;
    };

    # Git Tui
    programs.lazygit = {
      enable = true;
    };
  };
}
