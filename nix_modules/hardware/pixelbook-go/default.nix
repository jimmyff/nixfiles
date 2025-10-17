{ pkgs, lib, ... }:
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
  # NOTE: These kernel params override nixos-hardware settings (no lib.mkDefault)
  boot.kernelParams = [
    # Enable Intel AVS audio driver with debug for troubleshooting
    "snd_intel_avs.enable_debug=1"

    # Intel graphics power management fixes for suspend/resume issues
    # These MUST override nixos-hardware's kaby-lake defaults which enable PSR/FBC/GuC
    "i915.enable_psr=0"    # Disable panel self refresh (causes black screen on resume)
    "i915.enable_fbc=0"    # Disable framebuffer compression (can cause display glitches)
    "i915.enable_guc=0"    # Disable GuC firmware (problematic on some Chromebooks)
    "i915.enable_dc=0"     # Disable display C-states (critical for resume stability)

    # Chromebook-specific suspend/resume fixes
    "button.lid_init_state=open"  # Fix lid switch state detection

    # Logging
    "loglevel=4"
  ];

  # AVS driver modprobe configuration (critical for MAX98373 topology loading)
  boot.extraModprobeConfig = ''
    # Intel AVS driver configuration for Chromebooks
    options snd-intel-dspcfg dsp_driver=4
    options snd-soc-avs ignore_fw_version=1
    options snd-soc-avs obsolete_card_names=1
  '';

  # Additional udev rules for Chromebook audio and power management
  services.udev.extraRules = ''
    # Set audio device permissions for da7219 codec
    SUBSYSTEM=="sound", KERNEL=="card*", ATTRS{id}=="avsda7219", TAG+="uaccess"

    # Power management for audio devices - keep HDA powered during suspend
    SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x9dc8", ATTR{power/control}="on"

    # Disable autosuspend for USB controller to prevent spurious wakeups
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{class}=="0x0c03*", ATTR{power/control}="on"
  '';

  # Force s2idle sleep mode (systemd approach is more reliable than kernel param)
  # This prevents the system from using problematic S3 "deep" sleep on Chromebooks
  systemd.sleep.extraConfig = ''
    [Sleep]
    SuspendMode=s2idle
    HibernateMode=platform shutdown
    SuspendState=freeze
  '';

  # Disable problematic ACPI wakeup sources that can cause spurious wakeups/crashes
  # USB controller (XHCI) wakeup is particularly problematic on Chromebooks
  systemd.services.disable-acpi-wakeup = {
    description = "Disable problematic ACPI wakeup sources";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    script = ''
      # Disable USB controller wakeup if enabled (toggle by writing device name)
      if grep -q "XHCI.*enabled" /proc/acpi/wakeup; then
        echo XHCI > /proc/acpi/wakeup || true
      fi

      # Ensure LID0 is enabled for wakeup
      if grep -q "LID0.*disabled" /proc/acpi/wakeup; then
        echo LID0 > /proc/acpi/wakeup || true
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}