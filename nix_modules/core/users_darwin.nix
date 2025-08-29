
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

  system.activationScripts.ensureNuShell.text = ''
    target="${pkgs.nushell}/bin/nu"
    current="$(dscl . -read /Users/${username} UserShell | awk '{print $2}')"
    if [ "$current" != "$target" ]; then
      echo "Setting login shell for ${username} to $target"
      chsh -s "$target" ${username} || dscl . -change /Users/${username} UserShell "$current" "$target"
    fi
  '';

  nix.settings.trusted-users = [ username ];
}