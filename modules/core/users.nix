
{ pkgs-dev-tools, hostname, username, ... }:

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
    shell = pkgs-dev-tools.nushell;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAaZzF+34ChHrzl1Zr3crf60Snog3AQaHCrPNegyDitC jimmyff"
    ];
  };

  nix.settings.trusted-users = [ username ];
}