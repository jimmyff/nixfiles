{ pkgs, ... }:
let
  # MAX98373 topology file for Pixelbook Go speakers
  max98373-topology = pkgs.runCommand "max98373-topology" {} ''
    mkdir -p $out/lib/firmware/intel/avs
    cp ${./max98373-tplg.bin} $out/lib/firmware/intel/avs/max98373-tplg.bin
    chmod 644 $out/lib/firmware/intel/avs/max98373-tplg.bin
  '';
in
{
  # PIXELBOOK GO AUDIO CONFIGURATION
  # ================================
  # 
  # This module contains Pixelbook Go specific audio configuration required
  # to enable the MAX98373 speaker codec with Intel AVS driver.
  # 
  # BACKGROUND:
  # - Hardware: da7219 (headphone), max98373 (speakers), dmic (mic)
  # - Solution: WeirdTreeThing/chromebook-linux-audio script for Atlas/KBL platform
  # - Critical files: AVS topology, modprobe config, firmware
  # 
  # IMPLEMENTATION:
  # ✅ MAX98373 topology file: /lib/firmware/intel/avs/max98373-tplg.bin
  # ✅ AVS modprobe configuration (dsp_driver=4, ignore_fw_version=1)
  # ✅ Kernel debug parameters for troubleshooting
  # ✅ Hardware-specific udev rules

  # Add firmware packages for Chromebook audio hardware
  hardware.firmware = with pkgs; [
    linux-firmware
    sof-firmware
    max98373-topology  # MAX98373 topology file for speakers
  ];

  # Enable all firmware for Intel AVS topology files
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  # Add ALSA UCM configuration and audio management packages
  environment.systemPackages = with pkgs; [
    alsa-ucm-conf
    alsa-utils
    pavucontrol
    pulseaudio # for pactl command
  ];

  # Intel AVS driver configuration (from WeirdTreeThing/chromebook-linux-audio)
  boot.kernelParams = [
    # Enable Intel AVS audio driver with debug for troubleshooting
    "snd_intel_avs.enable_debug=1"
    
    # Intel graphics power management fixes for suspend/resume issues
    "i915.enable_psr=0"    # Disable panel self refresh (can cause resume issues)
    "i915.enable_fbc=0"    # Disable framebuffer compression if causing problems
    "i915.enable_guc=0"    # Disable GuC firmware loading (sometimes problematic)
  ];

  # AVS driver modprobe configuration (critical for MAX98373 topology loading)
  boot.extraModprobeConfig = ''
    # Intel AVS driver configuration for Chromebooks
    options snd-intel-dspcfg dsp_driver=4
    options snd-soc-avs ignore_fw_version=1
    options snd-soc-avs obsolete_card_names=1
  '';

  # Additional udev rules for Chromebook audio devices
  services.udev.extraRules = ''
    # Set audio device permissions for da7219 codec
    SUBSYSTEM=="sound", KERNEL=="card*", ATTRS{id}=="avsda7219", TAG+="uaccess"
    
    # Power management for audio devices
    SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x9dc8", ATTR{power/control}="on"
  '';
}