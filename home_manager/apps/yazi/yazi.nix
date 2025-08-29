{ pkgs, lib, config, ... }: {

    options = {

        yazi_module.enable = lib.mkEnableOption "enables yazi_module";

    };

    config = lib.mkIf config.yazi_module.enable {

        programs.yazi = {
            enable = true;
            settings = {
                manager = {
                    show_hidden = true;
                    sort_by = "mtime";
                    sort_dir_first = true;
                    sort_reverse = true;
                };
            };
        };

    };
}