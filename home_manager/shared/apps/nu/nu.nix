{
  pkgs,
  username,
  config,
  lib,
  ...
}: {
  programs = {
    # Docs: https://www.nushell.sh/book/configuration.html
    nushell = {
      enable = true;

      environmentVariables =
        config.home.sessionVariables
        // {
          # Force nushell to use home-manager managed config directory
          NU_CONFIG_PATH = "${config.xdg.configHome}/nushell";
          # Flutter and Android SDK environment variables
          ANDROID_HOME = "${config.home.homeDirectory}/.local/share/android/sdk";
          FLUTTER_ROOT = "${config.home.homeDirectory}/.local/share/flutter";
          PUB_CACHE = "${config.home.homeDirectory}/.cache/flutter/pub-cache";
        };

      # The config.nu can be anywhere you want if you like to edit your Nushell with Nu
      # configFile.source = ./.../config.nu;
      # for editing directly to config.nu
      extraConfig = ''
        let carapace_completer = {|spans|
        carapace $spans.0 nushell ...$spans | from json
        }
        $env.config = {
          show_banner: false,
          buffer_editor: "hx",
          completions: {
          case_sensitive: false   # case-sensitive completions
          quick: true             # set to false to prevent auto-selecting completions
          partial: true           # set to false to prevent partial filling of the prompt
          algorithm: "fuzzy"      # prefix or fuzzy
          external: {
              # set to false to prevent nushell looking into $env.PATH to find more suggestions
              enable: true
              # set to lower can improve completion performance at the cost of omitting some options
              max_results: 100
              completer: $carapace_completer # check 'carapace_completer'
            }
          }
        }
        $env.PATH ++= [
          "~/.nix-profile/bin"
          "~/.local/bin"
          "~/.pub-cache/bin"
          "~/.local/share/flutter/bin"
          "~/.local/share/android/sdk/platform-tools"
          "~/.local/share/android/sdk/tools/bin"
          "~/.local/share/android/sdk/cmdline-tools/latest/bin"
          "/etc/profiles/per-user/${username}/bin"
          "/run/current-system/sw/bin"
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

        ${lib.optionalString config.programs.atuin.enable ''
        # Atuin shell history integration
        # minimum supported version = 0.93.0
        module compat {
          export def --wrapped "random uuid -v 7" [...rest] { atuin uuid }
        }
        use (if not (
            (version).major > 0 or
            (version).minor >= 103
        ) { "compat" }) *

        $env.ATUIN_SESSION = (random uuid -v 7 | str replace -a "-" "")
        hide-env -i ATUIN_HISTORY_ID

        # Magic token to make sure we don't record commands run by keybindings
        let ATUIN_KEYBINDING_TOKEN = $"# (random uuid)"

        let _atuin_pre_execution = {||
            if ($nu | get history-enabled?) == false {
                return
            }
            let cmd = (commandline)
            if ($cmd | is-empty) {
                return
            }
            if not ($cmd | str starts-with $ATUIN_KEYBINDING_TOKEN) {
                $env.ATUIN_HISTORY_ID = (atuin history start -- $cmd)
            }
        }

        let _atuin_pre_prompt = {||
            let last_exit = $env.LAST_EXIT_CODE
            if 'ATUIN_HISTORY_ID' not-in $env {
                return
            }
            with-env { ATUIN_LOG: error } {
                if (version).minor >= 104 or (version).major > 0 {
                    job spawn -t atuin {
                        ^atuin history end $"--exit=($env.LAST_EXIT_CODE)" -- $env.ATUIN_HISTORY_ID | complete
                    } | ignore
                } else {
                    do { atuin history end $"--exit=($last_exit)" -- $env.ATUIN_HISTORY_ID } | complete
                }

            }
            hide-env ATUIN_HISTORY_ID
        }

        def _atuin_search_cmd [...flags: string] {
            [
                $ATUIN_KEYBINDING_TOKEN,
                ([
                    $'with-env { ATUIN_LOG: error, ATUIN_QUERY: (commandline) } {',
                        'commandline edit',
                        '(run-external atuin search',
                            ($flags | append [--interactive] | each {|e| $'"($e)"'}),
                        ' e>| str trim)',
                    $'}',
                ] | flatten | str join ' '),
            ] | str join "\n"
        }

        $env.config = ($env | default {} config).config
        $env.config = ($env.config | default {} hooks)
        $env.config = (
            $env.config | upsert hooks (
                $env.config.hooks
                | upsert pre_execution (
                    $env.config.hooks | get pre_execution? | default [] | append $_atuin_pre_execution)
                | upsert pre_prompt (
                    $env.config.hooks | get pre_prompt? | default [] | append $_atuin_pre_prompt)
            )
        )

        $env.config = ($env.config | default [] keybindings)

        $env.config = (
            $env.config | upsert keybindings (
                $env.config.keybindings
                | append {
                    name: atuin
                    modifier: control
                    keycode: char_r
                    mode: [emacs, vi_normal, vi_insert]
                    event: { send: executehostcommand cmd: (_atuin_search_cmd) }
                }
            )
        )

        $env.config = (
            $env.config | upsert keybindings (
                $env.config.keybindings
                | append {
                    name: atuin
                    modifier: none
                    keycode: up
                    mode: [emacs, vi_normal, vi_insert]
                    event: {
                        until: [
                            {send: menuup}
                            {send: executehostcommand cmd: (_atuin_search_cmd '--shell-up-key-binding') }
                        ]
                    }
                }
            )
        )
        ''}

      '';

      # Previous path settings:
      # $env.PATH = ($env.PATH |
      # split row (char esep) |
      # prepend /home/${username}/.apps |
      # append /usr/bin/env
      # )
      shellAliases = {
        vi = "hx";
        vim = "hx";
        nano = "hx";
      };
    };

    # Carapace / completions
    carapace.enable = true;
    carapace.enableNushellIntegration = true;

    # Starship / prompt
    starship = {
      enable = true;
      settings = {
        add_newline = true;
        character = {
          success_symbol = "[➜](bold green)";
          error_symbol = "[➜](bold red)";
        };
      };
    };

    # Zoxide / enhanced cd
    zoxide = {
      enable = true;
      enableNushellIntegration = true;
      options = [
        "--cmd cd"
      ];
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
    direnv = {
      enable = true;
      enableNushellIntegration = true;
      nix-direnv = {
        enable = true;
      };
    };
  };

  # Darwin-specific: Create symlink from default nushell location to home-manager config
  # This ensures all terminals use the same configuration
  home.activation = lib.mkIf pkgs.stdenv.isDarwin {
    setupNushellSymlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Path to the default macOS nushell config location
      NUSHELL_DEFAULT_PATH="$HOME/Library/Application Support/nushell"
      # Path to our home-manager nushell config
      NUSHELL_HM_PATH="${config.xdg.configHome}/nushell"
      
      echo "Setting up nushell configuration symlink for Darwin..."
      
      # Create the Application Support directory if it doesn't exist
      mkdir -p "$(dirname "$NUSHELL_DEFAULT_PATH")"
      
      # Check if the default path already exists
      if [ -e "$NUSHELL_DEFAULT_PATH" ] || [ -L "$NUSHELL_DEFAULT_PATH" ]; then
        # Check if it's already a symlink to our config
        if [ -L "$NUSHELL_DEFAULT_PATH" ] && [ "$(readlink "$NUSHELL_DEFAULT_PATH")" = "$NUSHELL_HM_PATH" ]; then
          echo "Nushell symlink already correctly configured"
        else
          echo "Backing up existing nushell config..."
          # Create backup with timestamp
          BACKUP_PATH="$NUSHELL_DEFAULT_PATH.backup.$(date +%Y%m%d_%H%M%S)"
          if ! mv "$NUSHELL_DEFAULT_PATH" "$BACKUP_PATH"; then
            echo "ERROR: Failed to backup existing nushell config" >&2
            exit 1
          fi
          echo "Existing config backed up to: $BACKUP_PATH"
        fi
      fi
      
      # Remove any existing symlink or directory (if backup failed above, we'll error out)
      rm -rf "$NUSHELL_DEFAULT_PATH" 2>/dev/null || true
      
      # Create the symlink
      echo "Creating symlink: $NUSHELL_DEFAULT_PATH -> $NUSHELL_HM_PATH"
      if ! ln -sf "$NUSHELL_HM_PATH" "$NUSHELL_DEFAULT_PATH"; then
        echo "ERROR: Failed to create nushell configuration symlink" >&2
        exit 1
      fi
      
      # Verify the symlink was created correctly
      if [ ! -L "$NUSHELL_DEFAULT_PATH" ] || [ "$(readlink "$NUSHELL_DEFAULT_PATH")" != "$NUSHELL_HM_PATH" ]; then
        echo "ERROR: Nushell symlink verification failed" >&2
        exit 1
      fi
      
      echo "Successfully configured nushell symlink on Darwin"
    '';
  };
}
