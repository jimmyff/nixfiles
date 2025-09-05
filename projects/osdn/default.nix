{ pkgs, lib }:

{
  # Repository information
  repo = "git@github.com:jimmyff/osdn_super.git";
  
  # Required packages for this project
  packages = with pkgs; [
    flutter  # Includes Dart SDK 3.9+ 
  ];
  
  # Development scripts to include
  scripts = {
    global = ["git-manager/gm.nu" "dartboard/dartboard.nu"];
    local = [];
  };
  
  # Project description
  description = "OSDN Platform";
}