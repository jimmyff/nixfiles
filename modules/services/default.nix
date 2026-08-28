{ ... }:
{
  # Opt-in daemons any host may enable, workstation or headless.
  # Desktop applications belong in ./modules/workstation/apps instead.
  imports = [
    ./nextdns.nix
    ./rclone.nix
    ./restic.nix
  ];
}
