{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    helix_module.enable = lib.mkEnableOption "enables helix_module";
  };

  config = lib.mkIf config.helix_module.enable {
    # Set hx as the default editor
    home.sessionVariables.EDITOR = "hx";

    # dprint configuration
    xdg.configFile."dprint/dprint.json".text = builtins.toJSON {
      markdown = {
        lineWidth = 80;
        textWrap = "maintain";
      };
      plugins = [
        "${pkgs.dprint-plugins.dprint-plugin-markdown}/plugin.wasm"
      ];
    };

    programs.helix = {
      enable = true;

      # Include necessary language servers and formatters
      extraPackages = with pkgs; [
        nil # Nix language server
        alejandra # Nix formatter
        flutter # Containers Dart SDK and language server
        taplo # TOML lsp
        lsp-ai # AI lsp
        marksman # MD lsp
        markdown-oxide # MD lsp
        dprint # code formatter
        dprint-plugins.dprint-plugin-markdown # md plugin
      ];

      settings = {
        # theme = "modus_vivendi_tinted";
        # theme = "kanagawa";
        theme = "dark_high_contrast";

        editor = {
          line-number = "relative";
          lsp.display-messages = true;
          lsp.display-inlay-hints = true;
          auto-format = true;
          bufferline = "never";
          soft-wrap.enable = true;
          cursorline = false;
          color-modes = true;
          popup-border = "all";
          rulers = [80];

          # inline-diagnostics
          end-of-line-diagnostics = "hint";
          inline-diagnostics = {
            cursor-line = "hint";
            other-lines = "error";
            prefix-len = 3;
          };

          # status
          statusline = {
            right = ["diagnostics" "workspace-diagnostics" "selections" "register" "position" "file-encoding"];
            diagnostics = ["warning" "error"];
            workspace-diagnostics = ["error"];
          };

          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
        };

        keys.normal = {
          # Yazi file explorer
          "C-y" = [
            ":sh rm -f /tmp/files2open"
            ":set mouse false"
            ":insert-output yazi \"%{buffer_name}\" --chooser-file=/tmp/files2open"
            ":redraw"
            ":set mouse true"
            ":open /tmp/files2open"
            "select_all"
            "split_selection_on_newline"
            "goto_file"
            ":buffer-close! /tmp/files2open"
          ];

          "C-:" = ":lsp-workspace-command";

          # Keybinds for focus switching
          "Cmd-C-h" = "jump_view_left";
          "Cmd-C-j" = "jump_view_down";
          "Cmd-C-k" = "jump_view_up";
          "Cmd-C-l" = "jump_view_right";

          # Smart tab recommendation
          "tab" = "move_parent_node_end";
          "S-tab" = "move_parent_node_start";
        };

        keys.insert = {
          # Smart tab recommendation
          "S-tab" = "move_parent_node_start";
        };

        keys.select = {
          # Smart tab recommendation
          "tab" = "extend_parent_node_end";
          "S-tab" = "move_parent_node_start";
        };
      };

      languages = {
        language-server = {
          lsp-ai = {
            command = "lsp-ai";
            models = {
              cs4 = {
                type = "anthropic";
                chat_endpoint = "https://api.anthropic.com/v1/messages";
                model = "claude-sonnet-4-20250514";
                auth_token_env_var_name = "ANTHROPIC_API_KEY";
                max_requests_per_second = 1;
              };
            };
          };
          nil = {
            command = "nil";
          };
          dart = {
            command = "dart";
            args = ["language-server" "--protocol=lsp"];
          };
          marksman = {
            command = "marksman";
            args = ["server"];
          };
          markdown-oxide = {
            command = "markdown-oxide";
          };
        };

        language = [
          {
            name = "nix";
            formatter = {
              command = "alejandra";
            };
            auto-format = true;
          }
          # Attempting to get Dart DAP connected. See:
          # https://github.com/dart-lang/sdk/blob/main/third_party/pkg/dap/tool/README.md
          # https://github.com/helix-editor/helix/wiki/Debugger-Configurations
          {
            name = "dart";
            language-servers = ["dart" "lsp-ai"];
            auto-format = true;
            formatter = {
              command = "dart";
              args = ["format"];
            };
            debugger = {
              name = "dart";
              transport = "stdio";
              command = "flutter";
              args = ["debug_adapter"];
              templates = [
                {
                  name = "launch";
                  request = "launch";
                  completion = [
                    {
                      name = "entrypoint";
                      completion = "filename";
                      default = "lib/main.dart";
                    }
                  ];
                  args = {program = "0";};
                }
              ];
            };
          }
          {
            name = "markdown";
            language-servers = ["marksman"];
            auto-format = true;
            soft-wrap = {
              enable = true;
              max-wrap = 80;
              wrap-at-text-width = true;
            };
            formatter = {
              command = "${pkgs.dprint}/bin/dprint";
              args = [
                "fmt"
                "--config"
                "${config.xdg.configHome}/dprint/dprint.json"
                "--stdin"
                "md"
              ];
            };
          }
          {
            name = "json";
            auto-format = true;
          }
          {
            name = "toml";
            auto-format = true;
          }
        ];
      };
    };
  };
}
