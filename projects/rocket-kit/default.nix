{ pkgs, lib }:

{
  # Repository information
  repo = "git@github.com:jimmyff/rocket-kit.git";
  
  # Required packages for this project
  # Flutter and Android SDK are provided by Android Studio instead of Nix
  # This avoids iOS build issues where Xcode cannot write to read-only Flutter root
  # See: https://github.com/flutter/flutter/pull/155139
  packages = with pkgs; [
    # flutter managed by Android Studio
  ];
  
  # Development scripts to include
  scripts = {
    global = ["git-manager/gm.nu" "dartboard/dartboard.nu"];
    local = [];
  };
  
  # Project description
  description = "Rocket Kit - Flutter/Dart development toolkit";
}