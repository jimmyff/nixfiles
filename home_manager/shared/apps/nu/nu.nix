{
  pkgs-apps,
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
in {
  programs = {
    # Docs: https://www.nushell.sh/book/configuration.html
    nushell = {
      enable = true;

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
        # Most paths should now be inherited from the system environment
        # Only add paths that are truly custom and not provided by Nix modules
        $env.PATH ++= [
          "~/.local/bin"
          "${config.xdg.cacheHome}/dart-pub/bin"
        ]

        # rclone config encryption password (if available)
        if ("/run/agenix/rclone-config-pass" | path exists) {
          $env.RCLONE_CONFIG_PASS = (open /run/agenix/rclone-config-pass | str trim)
        }

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
        # vi = "hx";
        # vim = "hx";
        # nano = "hx";
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
  home.activation = sharedLib.mkDarwinAppSupportSymlink {appName = "nushell";};
}
