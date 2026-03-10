{
  pkgs-apps,
  lib,
  config,
  ...
}: {
  options = {
    atuin_module.enable = lib.mkEnableOption "enables atuin_module";
  };

  config = lib.mkIf config.atuin_module.enable {
    programs.atuin = {
      enable = true;
      enableNushellIntegration = lib.mkIf config.programs.nushell.enable true;
    };
  };
}
