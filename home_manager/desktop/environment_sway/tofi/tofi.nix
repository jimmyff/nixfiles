{ pkgs, lib, config, ... }: 

let 

  # Jimmy's power menu
  tofiPowerMenu = pkgs.writeScriptBin "tofi-power-menu" ''
    #!${pkgs.nushell}/bin/nu

    # A simple list of strings for the menu options
    let options = [
        "Lock"
        "Sleep"
        "Reboot"
        "Logout"
        "Shutdown"
    ]

    # Pipe the list to tofi. The `try` block handles the user pressing Esc.
    try {
        # `str join` creates the newline-separated string tofi expects
        let chosen = ($options | str join "\n" | ${pkgs.tofi}/bin/tofi --prompt-text "\u{23fb}")

        match $chosen {
            "Lock" => { swaylock }
            "Sleep" => { ${pkgs.systemd}/bin/systemctl suspend }
            "Reboot" => { ${pkgs.systemd}/bin/systemctl reboot }
            "Logout" => { swaymsg exit }
            "Shutdown" => { ${pkgs.systemd}/bin/systemctl poweroff }
        }
    }
  '';
    in
    {

    options = {

        tofi_module.enable = lib.mkEnableOption "enables tofi_module";

    };

    config = lib.mkIf config.tofi_module.enable {

        programs.tofi = {
            enable = true;
            settings = {
                                
                prompt-text = ">";
                prompt-padding = 4;
                font = "JetBrainsMono Nerd Font";
                font-size = 16;
                height = "100%";
                width = "100%";
                num-results = 8;
                outline-width = 0;
                border-width = 0;
                padding-left = "35%";
                padding-top = "30%";
                result-spacing = 8;

                # Catppuccin Mocha
                text-color          = "#cdd6f4";
                prompt-color        = "#f38ba8";
                selection-color     = "#f9e2af";
                background-color    = "#1e1e2e";
            };
        };


        home.packages = [
            tofiPowerMenu
        ];
    };
}