{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    zed_module.enable = lib.mkEnableOption "enables zed_module";
  };

  config = lib.mkIf config.zed_module.enable {
    programs.zed-editor = {
      enable = true;

      extensions = [
        "dart"
        # "nix"
        "modus-themes"
      ];

      userSettings = {
        agent = {
          use_modifier_to_send = true;
          play_sound_when_agent_done = false;
        };

        agent_servers = {
          claude = {
            command = "claude";
            args = [];
            env = {};
          };
          gemini = {
            command = "gemini";
            args = [];
            env = {};
          };
        };

        buffer_font_family = "JetBrainsMono Nerd Font";
        ui_font_family = "JetBrainsMono Nerd Font";
        buffer_font_size = 13;
        ui_font_size = 13;
        theme = "Modus Vivendi Tinted";
        vim_mode = true;

        telemetry = {
          diagnostics = false;
          metrics = false;
        };

        # bindings = {
        #   "cmd-alt-g" = ["agent::NewExternalAgentThread" { agent = "gemini"; }];
        #   "cmd-alt-c" = ["agent::NewExternalAgentThread" { agent = "claude"; }];
        # };
      };
    };
  };
}
