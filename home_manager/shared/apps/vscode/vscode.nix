{ pkgs, lib, config, ... }: {

    options = {
        vscode_module.enable = lib.mkEnableOption "enables vscode_module";
    };

    config = lib.mkIf config.vscode_module.enable {
        home.packages = [
            # pkgs.code-cursor
            pkgs.vscode
        ];
    };
}