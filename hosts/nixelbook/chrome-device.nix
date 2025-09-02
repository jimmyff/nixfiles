{ config, lib, pkgs, ... }:

{
  # Chromebook-specific audio configuration for Pixelbook Go (atlas)
  # Based on chromebook-linux-audio and NixOS Chromebook guides
  
  # Enable SOF firmware for audio
  hardware.firmware = [ pkgs.sof-firmware pkgs.linux-firmware ];
  
  # SOF firmware should handle Pixelbook Go (atlas) audio automatically
  # No additional ChromeOS-specific firmware extraction needed
  
  # Basic PipeWire/Wireplumber configuration for SOF audio
  # SOF drivers should handle audio configuration automatically
  
  # Kernel module configuration for Chromebook audio (SOF driver)
  boot.kernelModules = [ "snd_sof_pci_intel_skl" ];
  
  # Modprobe options for SOF audio (Kaby Lake generation - atlas board)
  boot.extraModprobeConfig = ''
    # SOF audio driver options for Pixelbook Go
    options snd_hda_intel dsp_driver=1
    options snd_sof sof_debug=0
  '';
  
  # Additional audio packages that might be needed
  environment.systemPackages = with pkgs; [
    alsa-utils
    pavucontrol
    pulseaudio # for pactl command
  ];
}