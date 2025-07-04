{pkgs, lib, ... }: {

  imports = [
    ./desktop_system.nix
    ./greeter/greetd.nix
    ./sound.nix
    ./power.nix
  ];


  system = {
    stateVersion = 6;

    defaults = {
      menuExtraClock.Show24Hour = true;  # show 24 hour clock

    };
  };

}