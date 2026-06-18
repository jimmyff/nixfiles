{
  lib,
  config,
  ...
}: {
  options = {
    git_module.enable = lib.mkEnableOption "enables git_module";
  };

  config = lib.mkIf config.git_module.enable {
    programs.git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user = {
          name = "jimmyff";
          email = "code@rocketware.co.uk";
        };
        # `git sdiff` for on-demand side-by-side view
        alias.sdiff = "!git -c delta.side-by-side=true diff";
        # Pin effortLevel in Claude's settings.json (see .gitattributes).
        filter.claude-settings.clean = "jq --indent 2 '.effortLevel = \"xhigh\"'";
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
