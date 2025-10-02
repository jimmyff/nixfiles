{ pkgs-desktop, lib, config, ... }:

let

  # Jimmy's power menu
  tofiPowerMenu = pkgs-desktop.writeScriptBin "tofi-power-menu" ''
    #!${pkgs-desktop.nushell}/bin/nu

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
        let chosen = ($options | str join "\n" | ${pkgs-desktop.tofi}/bin/tofi --prompt-text "\u{23fb}")

        match $chosen {
            "Lock" => { swaylock }
            "Sleep" => { ${pkgs-desktop.systemd}/bin/systemctl suspend }
            "Reboot" => { ${pkgs-desktop.systemd}/bin/systemctl reboot }
            "Logout" => { swaymsg exit }
            "Shutdown" => { ${pkgs-desktop.systemd}/bin/systemctl poweroff }
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

                # Modus Vivendi Tinted colors
                text-color          = "#ffffff";
                prompt-color        = "#79a8ff";
                selection-color     = "#fec43f";
                background-color    = "#0d0e1c";
            };
        };


        home.packages = [
            tofiPowerMenu
        ];
    };
}