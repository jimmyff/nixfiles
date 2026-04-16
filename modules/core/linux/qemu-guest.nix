{
  lib,
  config,
  ...
}: let
  cfg = config.qemu-guest;
in {
  options.qemu-guest = {
    enable = lib.mkEnableOption "QEMU guest agent (for Proxmox VM visibility and clean shutdown)";
  };

  config = lib.mkIf cfg.enable {
    services.qemuGuest.enable = true;
  };
}
