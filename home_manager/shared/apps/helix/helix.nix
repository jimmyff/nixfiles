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
    # ================================================================
    # ENVIRONMENT SETUP
    # ================================================================

    # Set helix as the default system editor
    home.sessionVariables.EDITOR = "hx";

    # ================================================================
    # EXTERNAL TOOL CONFIGURATIONS
    # ================================================================

    # Configure dprint formatter for markdown files
    xdg.configFile."dprint/dprint.json".text = builtins.toJSON {
      markdown = {
        lineWidth = 80;
        textWrap = "maintain";
      };
      plugins = [
        "${pkgs.dprint-plugins.dprint-plugin-markdown}/plugin.wasm"
      ];
    };

    # Custom helix theme (symlinked for real-time editing)
    home.file.".config/helix/themes/modus_vivendi_tinted_plus.toml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/home_manager/shared/apps/helix/modus_vivendi_tinted_plus.toml";

    # ================================================================
    # HELIX CONFIGURATION
    # ================================================================

    programs.helix = {
      enable = true;

      # External packages required for language support
      extraPackages = with pkgs; [
        # Nix ecosystem
        nil # Nix language server
        alejandra # Nix formatter

        # Markdown ecosystem
        marksman # Markdown LSP server
        markdown-oxide # Alternative markdown LSP
        dprint # Code formatter
        dprint-plugins.dprint-plugin-markdown # Markdown plugin for dprint

        # Other language support
        taplo # TOML language server
        lsp-ai # AI-powered language server
      ];

      settings = {
        # ============================================================
        # APPEARANCE & THEME
        # ============================================================

        theme = "modus_vivendi_tinted_plus";

        # ============================================================
        # EDITOR BEHAVIOR
        # ============================================================

        editor = {
          # Line numbering and visual aids
          line-number = "relative";
          rulers = [80];
          cursorline = false;
          color-modes = true;
          popup-border = "all";

          # Text wrapping and formatting
          soft-wrap.enable = true;
          auto-format = true;
          bufferline = "never";

          # LSP and diagnostics display
          lsp.display-messages = true;
          lsp.display-inlay-hints = true;
          end-of-line-diagnostics = "hint";
          inline-diagnostics = {
            cursor-line = "hint";
            other-lines = "error";
            prefix-len = 3;
          };

          # Status line configuration
          statusline = {
            right = ["diagnostics" "workspace-diagnostics" "selections" "register" "position" "file-encoding"];
            diagnostics = ["warning" "error"];
            workspace-diagnostics = ["error"];
          };

          # Cursor appearance per mode
          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
        };

        # ============================================================
        # KEY BINDINGS
        # ============================================================

        # Normal mode keybindings
        keys.normal = {
          # File explorer integration (Yazi)
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

          # LSP workspace commands
          "C-:" = ":lsp-workspace-command";

          # Window/pane navigation
          "Cmd-C-h" = "jump_view_left";
          "Cmd-C-j" = "jump_view_down";
          "Cmd-C-k" = "jump_view_up";
          "Cmd-C-l" = "jump_view_right";

          # Smart syntax tree navigation
          "tab" = "move_parent_node_end";
          "S-tab" = "move_parent_node_start";
        };

        # Insert mode keybindings
        keys.insert = {
          "S-tab" = "move_parent_node_start";
        };

        # Select mode keybindings
        keys.select = {
          "tab" = "extend_parent_node_end";
          "S-tab" = "move_parent_node_start";
        };
      };

      # ============================================================
      # LANGUAGE SUPPORT
      # ============================================================

      languages = {
        # Language server definitions
        language-server = {
          # AI-powered language server
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

          # Nix language server
          nil = {
            command = "nil";
          };

          # Dart language server
          dart = {
            command = "dart";
            args = ["language-server" "--protocol=lsp"];
          };

          # Markdown language servers
          marksman = {
            command = "marksman";
            args = ["server"];
          };
          markdown-oxide = {
            command = "markdown-oxide";
          };
        };

        # Per-language configurations
        language = [
          # Nix language configuration
          {
            name = "nix";
            auto-format = true;
            formatter = {
              command = "alejandra";
            };
          }

          # Dart/Flutter language configuration with debugging support
          {
            name = "dart";
            language-servers = ["dart" "lsp-ai"];
            auto-format = true;
            formatter = {
              command = "dart";
              args = ["format"];
            };
            # Flutter debugging configuration
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

          # Markdown language configuration with word wrapping
          {
            name = "markdown";
            language-servers = ["marksman" "markdown-oxide"];
            auto-format = true;
            # Enable word wrapping at 80 characters for markdown
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

          # JSON language configuration
          {
            name = "json";
            auto-format = true;
          }

          # TOML language configuration
          {
            name = "toml";
            auto-format = true;
          }
        ];
      };
    };
  };
}
