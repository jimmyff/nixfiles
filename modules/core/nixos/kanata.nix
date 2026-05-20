# nixos specific configuration
{pkgs, lib, ... }: {
  services.kanata = {
    enable = true;
    keyboards = {
      internalKeyboard = {
        devices = [

        ];
        extraDefCfg = "process-unmapped-keys yes";

        configFile = ../../../dotfiles/kanata/kanata.kbd;

        # TCP IPC for layer switching. The upstream module restricts the
        # socket to loopback via systemd's IPAddressAllow/Deny and BPF filter,
        # so it is not reachable from the network.
        port = 5829;
      };
    };
  };
}
