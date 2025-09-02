{ pkgs, ... }:
{
  # Generic PipeWire audio configuration
  # Hardware-specific configuration is in hardware modules

  # Enable sound with pipewire
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
    
    # WirePlumber configuration to prevent audio device suspension
    wireplumber.extraConfig = {
      "10-disable-suspend" = {
        "wireplumber.profiles" = {
          main = {
            "monitor.alsa.rules" = [
              {
                matches = [
                  {
                    # Match any ALSA audio device
                    "device.name" = "~alsa_card.*";
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
}