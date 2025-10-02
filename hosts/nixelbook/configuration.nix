{
  config,
  pkgs-desktop,
  lib,
  inputs,
  username,
  ...
}: {
  imports = [
    ./hardware-configuration.nix

    # nixos specific configuration
    ../../nix_modules/core/nixos/kanata.nix

    # hardware specific configuration
    ../../nix_modules/hardware/pixelbook-go

    # desktop audio support
    ../../nix_modules/desktop/sound.nix

    # development environment
    ../../nix_modules/development
  ];

  networking.hostName = "nixelbook";

  # Development environment configuration
  development = {
    enable = true;
    projects = ["jimmyff-website" "rocket-kit" "osdn" "jotter"];
  };

  # Platform-specific development tools
  android.enable = false;
  dart.enable = true;
  rust.enable = true;
  linux-development.enable = true;

  # Applications
  signal.enable = true;
  google-chrome.enable = false;
  playwright.enable = false;

  # Pixelbook keyboard issue:
  # `sudo libinput debug-events` failed to show chromos key press
  # `sudo journalctl -f` gave the error:
  #  atkbd serio0: Unknown key released (translated set 2, code 0xd8 on isa0060/serio0).
  # I decided to set to keycode: 58	(Logo Left (-> Option))
  # Need to figure out how to configure `sudo setkeycodes e058 58`

  # Allow the user to control the keyboard backlight brightness
  services.udev.extraRules = ''
    SUBSYSTEM=="leds", KERNEL=="chromeos::kbd_backlight", GROUP="video", MODE="0664"
  '';

  # control the brightness of the screen (works with wayland)
  environment.systemPackages = [
    pkgs-desktop.brightnessctl
  ];

  # services.actkbd = {
  #   enable = true;
  #   bindings = [
  #     { keys = [ 224 ]; events = [ "key" ]; command = "/run/wrappers/bin/light -A 10"; }
  #     { keys = [ 225 ]; events = [ "key" ]; command = "/run/wrappers/bin/light -U 10"; }
  #   ];
  # };
}
