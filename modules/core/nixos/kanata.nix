# nixos specific configuration
{ pkgs, lib, config, ... }:
{
  options.kanata.platformKeys =
    import ../../../dotfiles/kanata/platformKeysOption.nix { inherit lib; };

  config.services.kanata = {
    enable = true;
    keyboards.internalKeyboard = {
      # Shared layer template + host key fragment + generated defcfg,
      # build-time validated with kanata --check.
      configFile = import ../../../dotfiles/kanata/mkConfig.nix {
        inherit pkgs;
        kanata = pkgs.kanata; # same package the service runs
        extraDefcfg = [ ];
        platformKeys = config.kanata.platformKeys;
      };

      # TCP IPC for layer switching. The upstream module restricts the socket to
      # loopback via systemd's IPAddressAllow/Deny and BPF filter, so it is not
      # reachable from the network.
      port = 5829;
    };
  };
}
