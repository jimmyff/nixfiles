{ pkgs, lib, config, ... }: {

    options = {
        neovim_module.enable = lib.mkEnableOption "enables neovim_module";
    };

    config = lib.mkIf config.neovim_module.enable {

        programs.neovim.enable = true;
        programs.neovim.defaultEditor = true;

        home.sessionVariables.EDITOR = "nvim";
      
    };
}