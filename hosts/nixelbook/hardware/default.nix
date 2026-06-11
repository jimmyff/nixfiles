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
  # Internal keyboard: kanata home-row mods + Pixelbook function-row layout.
  kanata.platformKeys = import ./kanata-fn.nix;

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

    # Force s2idle: this hardware has no working S3 firmware path.
    # systemd's old `SuspendMode=` option (sleep.conf) is silently ignored
    # in current systemd, so this kernel param is the only working mechanism.
    "mem_sleep_default=s2idle"

    # `systemctl poweroff` has been observed to hang in kernel_power_off()
    # on this device, producing an unresponsive lit screen. Force ACPI
    # shutdown semantics, which the EC seems to honor more cleanly.
    "reboot=acpi"

    # Logging
    "loglevel=4"
  ];

  # AVS driver modprobe configuration (critical for MAX98373 topology loading)
  boot.extraModprobeConfig = ''
    # Intel AVS driver configuration for Chromebooks
    options snd-intel-dspcfg dsp_driver=4
    options snd-soc-avs ignore_fw_version=1
  '';

  # da7219 (headphone codec) jack detection is broken: ACPI exposes the
  # codec's DAAD subnode without its _DSD properties ("Invalid jack detect
  # rate" in dmesg), so the HiFi UCM profile is never marked available and
  # only an unusable Pro Audio fallback remains. Hide the card to keep the
  # output picker clean — use a USB-C dongle for wired audio. A proper fix
  # would need an SSDT override to inject the missing _DSD properties.
  services.pipewire.wireplumber.extraConfig."51-disable-broken-da7219" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "device.name" = "~alsa_card\\.platform-avs_da7219.*"; }
        ];
        actions = {
          update-props = {
            "device.disabled" = true;
          };
        };
      }
    ];
  };

  # Additional udev rules for Chromebook audio and power management
  services.udev.extraRules = ''
    # Set audio device permissions for da7219 codec
    SUBSYSTEM=="sound", KERNEL=="card*", ATTRS{id}=="avsda7219", TAG+="uaccess"

    # Power management for audio devices - keep HDA powered during suspend
    SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x9dc8", ATTR{power/control}="on"

    # Disable autosuspend for USB controller to prevent spurious wakeups
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{class}=="0x0c03*", ATTR{power/control}="on"
  '';

  # s2idle is forced via the `mem_sleep_default=s2idle` kernel param (see
  # boot.kernelParams above). systemd removed `SuspendMode=` from sleep.conf,
  # so only the kernel param has effect now.
  systemd.sleep.extraConfig = ''
    [Sleep]
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