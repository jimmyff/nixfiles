
{ pkgs-desktop, ... }:
{
  # fonts: do these need to be system wide?
  fonts.packages = with pkgs-desktop; [
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
    nerd-fonts.noto
    nerd-fonts.hack
    nerd-fonts.jetbrains-mono
  ];

}