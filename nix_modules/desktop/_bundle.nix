{pkgs, lib, ... }: {

  imports = [
    ./desktop_system.nix
    ./sound.nix

    # Sway
    # ./environment_sway/_bundle.nix
        
    # Cosmic
    ./environment_cosmic/_bundle.nix
  ];

}
