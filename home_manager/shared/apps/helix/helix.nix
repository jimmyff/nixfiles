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

    programs.helix = {
      enable = true;

      # Include necessary language servers and formatters
      extraPackages = with pkgs; [
        nil # Nix language server
        alejandra # Nix formatter
        flutter # Containers Dart SDK and language server
        taplo # TOML lsp
        lsp-ai # AI lsp
      ];

      settings = {
        theme = "modus_vivendi_tinted";

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

          # inline-diagnostics
          end-of-line-diagnostics = "hint";
          inline-diagnostics = {
            cursor-line = "hint";
            other-lines = "error";
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
          "Cmd-C-h" = "jump_view_left";
          "Cmd-C-j" = "jump_view_down";
          "Cmd-C-k" = "jump_view_up";
          "Cmd-C-l" = "jump_view_right";
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
            language-servers = ["dart" "lsp-api"];
            auto-format = true;
            rulers = [80];
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
            auto-format = true;
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
