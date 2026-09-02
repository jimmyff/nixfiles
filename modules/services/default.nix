{ ... }:
{
  # Opt-in daemons any host may enable, workstation or headless.
  # Desktop applications belong in ./modules/workstation/apps instead.
  imports = [
    ./nasbox-mounts.nix
    ./nextdns.nix
    ./rclone.nix
    ./restic.nix
  ];
}
