
{ pkgs, hostname, username, ... }:

#############################################################
#
#  Host & Users configuration
#
#############################################################

{
 
  # Update the computer name to the host name
  #networking.computerName = networking.hostName;
  #system.defaults.smb.NetBIOSName = networking.hostName;

  users.users."${username}"= {
    home = "/home/${username}";
    description = username;
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "video" ];
    shell = pkgs.nushell;
  };

  nix.settings.trusted-users = [ username ];
}