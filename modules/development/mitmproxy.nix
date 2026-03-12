{
  pkgs-stable,
  lib,
  config,
  ...
}: let
  cfg = config.mitmproxy;
in {
  options.mitmproxy = {
    enable = lib.mkEnableOption "mitmproxy HTTPS debugging proxy";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs-stable.mitmproxy];
  };
}
