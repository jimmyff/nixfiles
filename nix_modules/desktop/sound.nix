{ pkgs, ... }:
let
  # MAX98373 topology file for Pixelbook Go speakers
  max98373-topology = pkgs.runCommand "max98373-topology" {} ''
    mkdir -p $out/lib/firmware/intel/avs
    cp ${../hardware/pixelbook-go/max98373-tplg.bin} $out/lib/firmware/intel/avs/max98373-tplg.bin
    chmod 644 $out/lib/firmware/intel/avs/max98373-tplg.bin
  '';
in
{
  # PIXELBOOK GO AUDIO DEBUG LOG
  # ============================
  # Problem: No audio output from speakers, MAX98373 codec fails to initialize
  # 
  # FINDINGS:
  # 1. Hardware detected: da7219 (headphone), max98373 (speakers), dmic (mic)
  # 2. Critical error: "load topology intel/avs/max98373-tplg.bin failed: -22"
  # 3. MAX98373 speakers never initialize - probe fails with error -22
  # 4. Only da7219 (headphone jack) card works, but no physical speakers connected
  # 5. Missing firmware: intel/avs/max98373-tplg.bin topology file
  # 6. ALSA mixer controls were muted by default (fixed manually with amixer)
  # 7. PipeWire shows 4 "Built-in Audio Pro" devices (duplicates + variants)
  # 
  # ATTEMPTED FIXES:
  # - Added alsa-ucm-conf package ❌ (didn't install properly)
  # - WirePlumber suspend configuration ❌ (devices still suspended)
  # - hardware.enableAllFirmware = true ❌ (topology still missing)
  # - Custom Debian firmware package ❌ (URL 404 error)
  # - Manual amixer controls ⚠️ (headphone works, but speakers don't exist)
  # 
  # SOLUTION FOUND: WeirdTreeThing/chromebook-linux-audio script ✅
  # - Atlas detected as KBL (Kabylake) platform using Intel AVS driver
  # - Script provides: AVS topology files, modprobe config, UCM configuration
  # - MX98373 devices found (not MX98357A, so no speaker damage risk)
  # 
  # IMPLEMENTATION STATUS:
  # ✅ Added max98373-tplg.bin topology file to /lib/firmware/intel/avs/
  # ✅ Added AVS modprobe configuration (dsp_driver=4, ignore_fw_version=1)
  # ✅ Files properly tracked in git under nix_modules/hardware/pixelbook-go/
  # ✅ NixOS rebuild completed without errors
  # 
  # NEXT: Reboot required! (chromebook-linux-audio: "2 or occasionally 3 reboots")
  # 
  # POST-REBOOT TESTING CHECKLIST:
  # 1. Check if MAX98373 speakers appear: cat /proc/asound/cards
  # 2. Look for successful topology loading: journalctl -b | grep -i "max98373\|topology"
  # 3. Test direct speaker output: speaker-test -D hw:max98373 (if device exists)
  # 4. Check PipeWire device detection: pactl list short sinks
  # 5. Test audio applications with speaker output
  # 6. Verify no more "avs_max98373 probe failed with error -22" messages
  # 7. May require 2-3 reboots according to Pixelbook Fedora guide

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # Enable WirePlumber session manager for better device management
    wireplumber.enable = true;
    
    # WirePlumber configuration to prevent audio suspension
    wireplumber.extraConfig = {
      "10-disable-suspend" = {
        "wireplumber.profiles" = {
          main = {
            "monitor.alsa.rules" = [
              {
                matches = [
                  {
                    # Match da7219 audio device
                    "device.name" = "~alsa_card.platform-avs_da7219.*";
                  }
                ];
                actions = {
                  update-props = {
                    "session.suspend-timeout-seconds" = 0;
                  };
                };
              }
            ];
          };
        };
      };
    };
  };

  # Add firmware packages for Chromebook audio hardware
  hardware.firmware = with pkgs; [
    linux-firmware
    sof-firmware
    max98373-topology  # MAX98373 topology file for speakers
  ];

  # Enable all firmware for Intel AVS topology files
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  # Add ALSA UCM configuration packages
  environment.systemPackages = with pkgs; [
    alsa-ucm-conf
  ];

  # Intel AVS driver configuration (from WeirdTreeThing/chromebook-linux-audio)
  boot.kernelParams = [
    # Enable Intel AVS audio driver with debug for troubleshooting
    "snd_intel_avs.enable_debug=1"
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