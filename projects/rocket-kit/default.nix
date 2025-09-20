{ pkgs, lib }:

{
  # Repository information
  repo = "git@github.com:jimmyff/rocket-kit.git";
  
  # Required packages for this project
  # Flutter and Dart are managed at the host level via dart.enable
  packages = with pkgs; [
    # No additional packages needed - Dart/Flutter provided by host configuration
  ];
  
  # Development scripts to include
  scripts = {
    global = ["git-manager/gm.nu" "dartboard/dartboard.nu" "flitter/flitter.rs"];
    local = [];
  };
  
  # Project description
  description = "Rocket Kit - Flutter/Dart development toolkit";
}