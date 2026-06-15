{
  pkgs-apps,
  pkgs-dev-tools,
  username,
  config,
  lib,
  inputs,
  ...
}: let
  sharedLib = import ../../lib.nix {
    inherit lib config;
    pkgs = pkgs-apps;
  };

  # Starship's Nushell integration, generated from the same starship the prompt
  # uses (so it stays version-consistent). We source this ourselves, guarded by
  # `$nu.is-interactive` (see the guarded `use` in extraConfig), instead of
  # letting HM inject it unconditionally — that injection runs even in
  # non-interactive shells (e.g. a session-launch `nu -l -c`) and exports
  # prompt vars containing ANSI control chars into the environment.
  starshipNushellInit = pkgs-apps.runCommand "starship-nushell-init.nu" { } ''
    ${config.programs.starship.package}/bin/starship init nu > $out
  '';
in {
  programs = {
    # Docs: https://www.nushell.sh/book/configuration.html
    nushell = {
      enable = true;
      package = pkgs-dev-tools.nushell;

      environmentVariables =
        config.home.sessionVariables
        // {
          # Force nushell to use home-manager managed config directory
          NU_CONFIG_PATH = "${config.xdg.configHome}/nushell";
          # FLUTTER_ROOT, ANDROID_HOME, JAVA_HOME, PUB_CACHE should be inherited from dart.nix and android.nix modules
        };

      # The config.nu can be anywhere you want if you like to edit your Nushell with Nu
      # configFile.source = ./.../config.nu;
      # for editing directly to config.nu
      extraConfig = ''
        # Carapace external completer (HM integration disabled, managed here)
        let carapace_completer = {|spans|
            # Let nushell handle its own commands and aliases (builtins, custom, aliases)
            let cmd = $spans.0
            if (scope commands | where name == $cmd | is-not-empty) or (scope aliases | where name == $cmd | is-not-empty) {
                return null
            }

            carapace $cmd nushell ...$spans | from json
        }

        # Merge config to preserve hooks/keybindings set by other integrations (atuin etc)
        $env.config = ($env.config? | default {} | merge {
          show_banner: false
          buffer_editor: "hx"
          completions: {
            case_sensitive: false
            quick: true
            partial: true
            algorithm: "fuzzy"
            external: {
              enable: true
              max_results: 100
              completer: $carapace_completer
            }
          }
        })

        # Most paths should now be inherited from the system environment
        # Only add paths that are truly custom and not provided by Nix modules
        $env.PATH ++= [
          "~/.local/bin"
          "${config.xdg.cacheHome}/dart-pub/bin"
          "/opt/homebrew/bin"
        ]

        def --env y [...args] {
          let tmp = (mktemp -t "yazi-cwd.XXXXXX")
          yazi ...$args --cwd-file $tmp
          let cwd = (open $tmp)
          if $cwd != "" and $cwd != $env.PWD {
            cd $cwd
          }
          rm -fp $tmp
        }

        # Atuin nushell integration is configured in atuin.nix

        # Starship prompt — interactive sessions only. Skipping it for
        # non-interactive nu keeps prompt vars (which carry ANSI control chars)
        # out of the environment that a session launcher would import.
        if $nu.is-interactive { use ${starshipNushellInit} }

      '';

      # Previous path settings:
      # $env.PATH = ($env.PATH |
      # split row (char esep) |
      # prepend /home/${username}/.apps |
      # append /usr/bin/env
      # )
      shellAliases = {
        x = "mux";
        # vi = "hx";
        # vim = "hx";
        # nano = "hx";
      };
    };

    # Carapace / completions (nushell integration managed in extraConfig above)
    carapace.enable = true;
    carapace.enableNushellIntegration = false;

    # Starship / prompt
    starship = {
      enable = true;
      # Sourced manually (interactive-only) in nushell extraConfig above; see
      # the starshipNushellInit derivation. HM's default injection is
      # unconditional and would set prompt vars in non-interactive shells too.
      enableNushellIntegration = false;
      settings = {
        scan_timeout = 150; # raised default for low-end hardware (nixelbook)
        add_newline = true;
        character = {
          success_symbol = "[➜](bold green)";
          error_symbol = "[➜](bold red)";
        };
        gcloud.format = "on [\$symbol\$project](\$style) ";
        directory = {
          truncate_to_repo = false;
          truncation_length = 8;
          substitutions = {
            "Projects" = "🚀";
            "workspace" = "🛠️";
            "apps" = "📱";
            "cloud" = "☁️";
            "packages" = "📦";
          };
        };
        dart.disabled = true;
        git_branch.ignore_branches = [ "main" ];
        nix_shell = {
          symbol = "❄️";
          format = "via [\$symbol\$state](\$style) ";
          impure_msg = "!";
          pure_msg = "";
        };
      };
    };

    # Zoxide / enhanced cd
    zoxide = {
      enable = true;
      enableNushellIntegration = true;
    };

    # FD / find
    fd = {
      enable = true;
    };

    # FZF / fuzzy finder
    fzf = {
      enable = true;
      # enableNushellIntegration = true;
    };

    # Direnv / automatic environment loading
    # TODO: move back to default (pkgs-stable) once NixOS/nix#15638 lands
    direnv = {
      enable = true;
      package = pkgs-dev-tools.direnv;
      enableNushellIntegration = true;
      nix-direnv = {
        enable = true;
        package = pkgs-dev-tools.nix-direnv;
      };
    };
  };

  # Darwin-specific: Create symlink from default nushell location to home-manager config
  home.activation = sharedLib.mkDarwinAppSupportSymlink {appName = "nushell";};
}
