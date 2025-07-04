{ pkgs, lib, config, ... }: {

    options = {
        chromium_module.enable = lib.mkEnableOption "enables chromium_module";
    };

    config = lib.mkIf config.chromium_module.enable {

        home.packages = [
            pkgs.chromium			# browser			
            pkgs.google-chrome		# browser
        ];

        home.sessionVariables.BROWSER = "google-chrome-stable";
    };
}