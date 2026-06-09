{ pkgs-apps, lib, config, ... }: {
  options.mux_module.enable = lib.mkEnableOption "mux zellij workspace launcher";

  config = lib.mkIf config.mux_module.enable {
    # `mux` resolves a session name + private layout from the cwd and
    # attaches to (or creates) the matching zellij session. See mux.nu.
    home.packages = [
      (pkgs-apps.writeScriptBin "mux"
        ("#!${pkgs-apps.nushell}/bin/nu\n" + builtins.readFile ./mux.nu))
    ];
  };
}
