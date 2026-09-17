{ pkgs-apps, lib, config, ... }: {
  options.waypiper_module.enable = lib.mkEnableOption "waypiper remote Wayland app forwarding";

  config = lib.mkIf config.waypiper_module.enable {
    home.packages = [
      pkgs-apps.waypipe
      (pkgs-apps.writeScriptBin "waypiper"
        ("#!${pkgs-apps.nushell}/bin/nu\n" + builtins.readFile ./waypiper.nu))
    ];
  };
}
