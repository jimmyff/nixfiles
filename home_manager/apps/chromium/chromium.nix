{ pkgs, lib, config, ... }: {

    options = {
        chromium_module.enable = lib.mkEnableOption "enables chromium_module";
    };

    config = lib.mkIf config.chromium_module.enable {

        home.packages = [
            #pkgs.google-chrome		# browser
        ];

        programs.chromium = {
            enable = true;
            extensions = [
                "nngceckbapebfimnlniiiahkandclblb" # bitwarden
                "eljbmlghnomdjgdjmbdekegdkbabckhm" # Dart debug
                "dbepggeogbaibhgnhhndojpepiihcmeb" # vimium
            ];
        };

        home.sessionVariables.BROWSER = "google-chrome-stable";
    };
}