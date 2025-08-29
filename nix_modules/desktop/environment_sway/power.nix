{ pkgs, ... }:
{
  # Power management
  powerManagement.enable = true;
  services.tlp.enable = true;
}