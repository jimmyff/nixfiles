{ config, pkgs, lib, inputs, username, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  networking.hostName = "nixelbook";

  # Pixelbook keyboard issue:
  # `sudo libinput debug-events` failed to show chromos key press
  # `sudo journalctl -f` gave the error:
  #  atkbd serio0: Unknown key released (translated set 2, code 0xd8 on isa0060/serio0).
  # I decided to set to keycode: 58	(Logo Left (-> Option))
  # Need to figure out how to configure `sudo setkeycodes e058 58`

  # control the brightness of the screen (works with wayland)
  environment.systemPackages = with pkgs; [
    pkgs.brightnessctl
  ];
  
  # services.actkbd = {
  #   enable = true;
  #   bindings = [
  #     { keys = [ 224 ]; events = [ "key" ]; command = "/run/wrappers/bin/light -A 10"; }
  #     { keys = [ 225 ]; events = [ "key" ]; command = "/run/wrappers/bin/light -U 10"; }
  #   ];
  # };
 
}
