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
    ../../modules/core/nixos/kanata.nix

    # hardware specific configuration
    ./hardware

    # desktop audio support
    ../../modules/workstation/desktop/sound.nix

    # gaming wrapper (suspends kanata + touchpad dwt while running)
    ../../modules/workstation/insertcoin.nix

    # development environment
    ../../modules/development
  ];

  networking.hostName = "nixelbook";

  # Development environment configuration
  development = {
    enable = true;
    projects = ["jimmyff-website" "rocket-kit" "osdn" "cache" "warcrest" "shed"];
  };

  # Platform-specific development tools
  android.enable = false;
  dart.enable = true;
  rust.enable = false;
  mitmproxy.enable = false;
  wireshark.enable = false;
  docker.enable = false;
  development.google-cloud-sdk = false;
  development.firebase-tools = false;

  # Applications
  cinny.enable = false; # 2026-02-20: temporarily disabled, nixpkgs version mismatch (cinny 4.10.3 vs cinny-desktop 4.10.2)
  little-snitch.enable = false;
  workstation-security.enable = true;
  signal.enable = true;
  google-chrome.enable = false;
  playwright.enable = false;
  nextdns.enable = true;
  nextdns.vaultFile = "nextdns_nixelbook.age";
  rclone.enable = true;
  minisign.enable = true;
  insertcoin = {
    enable = true;
    touchpad.enable = true;
  };

  # Editors (home-manager modules)
  home-manager.users.jimmyff.zed_module.enable = false; # Disable Zed to save disk space
  home-manager.users.jimmyff.thunderbird_module.enable = false; # Disable to save disk space

  # Suspend-on-lid-close intermittently fails to resume (black screen) despite
  # the i915/sleep/wakeup workarounds in hardware/default.nix. Lock instead —
  # the system stays running so opening the lid resumes reliably.
  services.logind.settings.Login.HandleLidSwitch = "lock";

  # Watchdog escape hatch: `systemctl poweroff` has been observed to hang in
  # kernel_power_off() on this device (lit-but-frozen screen). If shutdown
  # doesn't complete in 2 minutes, the hardware watchdog forces a reboot.
  systemd.watchdog.rebootTime = "2min";

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
