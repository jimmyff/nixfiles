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
      # Nushell is the primary shell; other shells' integrations stay off.
      enableBashIntegration = false;
      enableZshIntegration = false;
      enableFishIntegration = false;
      # Sourced manually below to remap its history keybinding.
      enableNushellIntegration = false;
    };

    # Full upstream channel set, version-matched to the installed binary.
    # recursive: links per-file, so custom channels can live alongside.
    xdg.configFile."television/cable" = {
      source = "${config.programs.television.package.src}/cable/unix";
      recursive = true;
    };

    # tv integration: ctrl-t smart autocomplete; history moved ctrl-r -> alt-r
    # so atuin keeps ctrl-r. The upstream script hardcodes both bindings.
    # macOS: alt-r never reaches the shell (kitty has no macos_option_as_alt, so
    # Option types characters, e.g. # on UK layout); run `tv nu-history` there.
    programs.nushell.extraConfig = lib.mkIf config.programs.nushell.enable ''
      source ${config.programs.television.package}/share/television/completion.nu
      $env.config.keybindings = ($env.config.keybindings | each {|kb|
          if $kb.name == "tv_history" { $kb | upsert modifier alt } else { $kb }
      })
    '';
  };
}
