
{ pkgs-desktop, ... }:
{

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 16;


  # allows sandboxed apps to access resources
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs-desktop.xdg-desktop-portal-gtk	  # Standard handler
      pkgs-desktop.gnome-keyring		      # for some apps
    ];

    # TODO: do something better here
    config.common.default = "*";
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1"; # Wayland support for chromium based apps

  # Touchpad support
  services.libinput = {
    enable = true;
    mouse.naturalScrolling = true;
    touchpad.naturalScrolling = true;
  };

  # Ignore the power off button
  services.logind.settings.Login.HandlePowerKey = "ignore";

  # gnome secrets vault
  services.gnome.gnome-keyring.enable = true;

  # Networking
  networking.networkmanager.enable = true;

   environment.systemPackages = [
    pkgs-desktop.networkmanagerapplet
  ];

  # Enable CUPS to print documents.
  services.printing.enable = true;

   # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };
}