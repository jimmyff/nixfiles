{
  pkgs-stable,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.wireshark;
in {
  options.wireshark = {
    enable = lib.mkEnableOption "Wireshark network protocol analyzer";
  };

  config = lib.mkIf cfg.enable (
    if pkgs-stable.stdenv.isDarwin
    then {
      environment.systemPackages = [pkgs-stable.wireshark];

      # Create access_bpf group and add the user via activation script
      system.activationScripts.postActivation.text = ''
        # Wireshark: ensure access_bpf group exists for BPF device access
        if ! dscl . -read /Groups/access_bpf &>/dev/null; then
          echo "Creating access_bpf group..."
          dseditgroup -o create access_bpf
        fi
        # Add user to access_bpf group
        dseditgroup -o edit -a "${username}" -t user access_bpf
      '';

      # Launch daemon to chmod BPF devices at boot
      launchd.daemons.chmod-bpf = {
        script = ''
          chgrp access_bpf /dev/bpf*
          chmod g+rw /dev/bpf*
        '';
        serviceConfig = {
          Label = "org.wireshark.ChmodBPF";
          RunAtLoad = true;
        };
      };
    }
    else {
      programs.wireshark = {
        enable = true;
        package = pkgs-stable.wireshark;
      };
    }
  );
}
