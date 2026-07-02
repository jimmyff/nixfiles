{
  pkgs-apps,
  lib,
  config,
  ...
}: {
  options = {
    television_module.enable = lib.mkEnableOption "enables television_module";
  };

  config = lib.mkIf config.television_module.enable {
    # Fuzzy finder / TUI. Binary is `tv`.
    # Docs: https://alexpasmantier.github.io/television/
    programs.television = {
      enable = true;
      package = pkgs-apps.television;
      # Shell integrations left off; nushell (primary shell) has no HM option.
      # Customise settings/channels here later.
    };
  };
}
