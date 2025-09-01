{
  pkgs,
  
  ...
}:
{

  # Enable the socmisc login manager
  services.displayManager.cosmic-greeter.enable = true;
  # Enable the cosmic desktop environment
  services.desktopManager.cosmic.enable = true;

  # services.displayManager.autoLogin = {
  #   enable = true;
  #   user = "jimmyff";
  # };

}