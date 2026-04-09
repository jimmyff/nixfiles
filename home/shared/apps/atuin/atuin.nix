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
      settings = {
        # Disable network call that pings api.atuin.sh to check for new releases
        update_check = false;
        # Skip storing commands matching built-in secret regexes (AWS keys, GH tokens, etc.)
        secrets_filter = true;
      };
    };
  };
}
