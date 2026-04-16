{ lib, config, username, ... }:

{
  options.desktop = {
    enable = lib.mkEnableOption "desktop environment and GUI applications";
  };

  imports = [
    ../shared/apps
    ./desktop/environment_cosmic
  ];

  config = {
    home = {
      username = username;
      stateVersion = "25.05";
      homeDirectory = "/home/${username}";

      sessionVariables = lib.mkIf config.desktop.enable {
        SSH_AUTH_SOCK = "/run/user/1000/gcr/ssh";
      };
    };

    # Disable GUI modules on headless systems
    cosmic_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);
    kitty_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);
    rio_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);
    alacritty_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);
    thunderbird_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);
    chromium_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);
    iamb_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);
    zed_module.enable = lib.mkIf (!config.desktop.enable) (lib.mkForce false);

    programs.home-manager.enable = true;
  };
}
