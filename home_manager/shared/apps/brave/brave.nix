{ pkgs-apps, lib, config, ... }: {

  options = {
    brave_module.enable = lib.mkEnableOption "Enable Brave browser";
  };

  config = lib.mkIf config.brave_module.enable {
    home.packages = [ pkgs-apps.brave ];
    
    home.sessionVariables.BROWSER = lib.mkIf (!config.librewolf_module.enable && !config.chromium_module.enable) "brave";
  };
}