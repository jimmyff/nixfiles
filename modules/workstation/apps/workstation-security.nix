{
  pkgs-stable,
  lib,
  config,
  ...
}: let
  cfg = config.workstation-security;
in {
  options.workstation-security = {
    enable = lib.mkEnableOption "Workstation security tools (Objective-See on macOS, OpenSnitch on Linux)";
  };

  config = lib.mkIf cfg.enable (
    if pkgs-stable.stdenv.isDarwin
    then {
      homebrew.casks = [
        # Objective-See security tools
        "lulu" # app firewall
        "blockblock" # persistence monitor
        "do-not-disturb" # physical access alerts
        "dhs" # dylib hijack scanner
        "kextviewr" # kernel extension viewer
        "knockknock" # persistent software scanner
        "netiquette" # network monitor
        "oversight" # mic/camera monitor
        "reikey" # keystroke logger detector
        "ransomwhere" # ransomware detector
        "taskexplorer" # process inspector
        "whatsyoursign" # code signature viewer
      ];
    }
    else {
      services.opensnitch.enable = true;
      environment.systemPackages = [
        pkgs-stable.opensnitch-ui
      ];
    }
  );
}
