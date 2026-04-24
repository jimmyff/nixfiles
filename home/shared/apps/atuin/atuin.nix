{
  pkgs-apps,
  lib,
  config,
  ...
}: {
  options = {
    atuin_module.enable = lib.mkEnableOption "enables atuin_module";
  };

  config = lib.mkIf config.atuin_module.enable {
    programs.atuin = {
      enable = true;
      # TODO: re-enable once nushell supports `job spawn -t` (atuin 18.15.2 generates -t, nushell 0.112.2 only has -d)
      enableNushellIntegration = false;
      settings = {
        # Disable network call that pings api.atuin.sh to check for new releases
        update_check = false;
        # Skip storing commands matching built-in secret regexes (AWS keys, GH tokens, etc.)
        secrets_filter = true;
      };
    };

    # Custom nushell integration (patched for nushell 0.112.2 compatibility)
    # Replaces HM's enableNushellIntegration which generates incompatible `job spawn -t`
    programs.nushell.extraConfig = lib.mkIf config.programs.nushell.enable ''
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
                  job spawn -d atuin {
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
                  `with-env { ATUIN_LOG: error, ATUIN_QUERY: (commandline) } {`,
                      ([
                          'let output = (run-external atuin search',
                          ($flags | append [--interactive] | each {|e| $'"($e)"'}),
                          'e>| str trim)',
                      ] | flatten | str join ' '),
                      'if ($output | str starts-with "__atuin_accept__:") {',
                      'commandline edit --accept ($output | str replace "__atuin_accept__:" "")',
                      '} else {',
                      'commandline edit $output',
                      '}',
                  `}`,
              ] | flatten | str join "\n"),
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
    '';
  };
}
