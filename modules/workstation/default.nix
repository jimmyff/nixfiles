{ ... }:
{
  imports = [
    ../core/shared/fonts.nix
    ./apps/cinny.nix
    ./apps/google-chrome.nix
    ./apps/workstation-security.nix
    ./apps/little-snitch.nix
    ./apps/minisign.nix
    ./apps/raycast.nix
    ./apps/picard.nix
    ./apps/signal.nix
    ./playwright.nix
  ];
}
