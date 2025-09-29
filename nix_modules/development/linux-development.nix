{
  inputs,
  pkgs,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.linux-development;
in {
  options.linux-development = {
    enable = lib.mkEnableOption "Linux development environment";
  };

  config = lib.mkIf cfg.enable {
    # Linux development packages
    environment.systemPackages = with pkgs; [
      gtk3
      gtk3.dev
      pkg-config
      glib
      glib.dev
      pango
      pango.dev
      cairo
      cairo.dev
      gdk-pixbuf
      gdk-pixbuf.dev
      atk
      atk.dev
      harfbuzz
      harfbuzz.dev
    ];

    # Environment variables for GTK development
    environment.variables = {
      PKG_CONFIG_PATH = lib.concatStringsSep ":" [
        "${pkgs.gtk3.dev}/lib/pkgconfig"
        "${pkgs.glib.dev}/lib/pkgconfig"
        "${pkgs.pango.dev}/lib/pkgconfig"
        "${pkgs.cairo.dev}/lib/pkgconfig"
        "${pkgs.gdk-pixbuf.dev}/lib/pkgconfig"
        "${pkgs.atk.dev}/lib/pkgconfig"
        "${pkgs.harfbuzz.dev}/lib/pkgconfig"
      ];
    };

    # Setup Linux development environment
    system.activationScripts.linuxDevelopmentSetup = {
      text = ''
        echo "🐧 Activated Linux development environment"
      '';
      deps = ["users" "groups"];
    };
  };
}