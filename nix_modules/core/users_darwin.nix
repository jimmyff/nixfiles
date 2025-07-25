
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
    home = "/Users/${username}";
    description = username;
    shell = pkgs.nushell;
  };

  nix.settings.trusted-users = [ username ];
}