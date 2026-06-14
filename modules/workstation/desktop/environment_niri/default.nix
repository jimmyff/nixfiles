{ ... }: {

  imports = [
    ./greeter/greetd.nix
    ./niri.nix
    ./thunar.nix
  ];

  # File manager — off for now; flip to true to bring Thunar back.
  thunar_module.enable = false;

  # Removable media automount (consumed by the home-manager udiskie service).
  services.udisks2.enable = true;

  # dconf/gsettings store — backs the home-manager dconf.settings (dark color-scheme).
  programs.dconf.enable = true;

  # Power management (matches the sway env)
  powerManagement.enable = true;
  services.tlp.enable = true;
}
