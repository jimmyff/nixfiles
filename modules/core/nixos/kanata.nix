# nixos specific configuration
{pkgs, lib, ... }: {
  services.kanata = {
    enable = true;
    keyboards = {
      internalKeyboard = {
        devices = [

        ];
        extraDefCfg = "process-unmapped-keys yes";

        
        configFile = ../../../dotfiles/kanata/kanata.kbd;
      };
    };
  };
}
