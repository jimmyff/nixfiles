{ pkgs, lib, config, ... }: {

    options = {

        yazi_module.enable = lib.mkEnableOption "enables yazi_module";

    };

    config = lib.mkIf config.yazi_module.enable {


        # https://yazi-rs.github.io/docs/configuration/overview/
        programs.yazi = {
            enable = true;
            settings = {
                mgr = {
                    show_hidden = true;
                    sort_by = "mtime";
                    sort_dir_first = true;
                    sort_reverse = true;
                };
            };
        };

    };
}
