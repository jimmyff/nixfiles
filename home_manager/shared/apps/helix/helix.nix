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
    programs.helix = {
      enable = true;

      # Include necessary language servers and formatters
      extraPackages = with pkgs; [
        nil # Nix language server
        alejandra # Nix formatter
        dart # Dart SDK and language server
      ];

      settings = {
        theme = "modus_vivendi_tinted";

        editor = {
          line-number = "relative";
          lsp.display-messages = true;
          auto-format = true;
          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
        };

        keys.normal = {
          space.f.f = ":open ~/."; # file picker
          space.w = ":write"; # save file
        };
      };

      languages = {
        language-server = {
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
          {
            name = "dart";
            language-servers = ["dart"];
            auto-format = true;
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
