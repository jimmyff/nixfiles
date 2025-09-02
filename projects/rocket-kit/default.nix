{ pkgs, lib }:

{
  # Repository information
  repo = "git@github.com:jimmyff/rocket-kit.git";
  
  # Required packages for this project
  packages = with pkgs; [
    dart
    flutter
  ];
  
  # Project description
  description = "Rocket Kit - Flutter/Dart development toolkit";
}