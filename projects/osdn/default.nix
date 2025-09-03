{ pkgs, lib }:

{
  # Repository information
  repo = "git@github.com:jimmyff/osdn_super.git";
  
  # Required packages for this project
  packages = with pkgs; [
    flutter  # Includes Dart SDK 3.9+ 
  ];
  
  # Project description
  description = "OSDN Platform";
}