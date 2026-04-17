{
  pkgs,
  lib,
}: {
  # Repository information
  repo = "git@github.com:jimmyff/shed.git";

  # Required packages for this project
  packages = with pkgs; [
  ];

  # Development scripts to include
  scripts = {
    global = [];
    local = [];
  };

  # Project description
  description = "Shed - Utilities, mini projects, and tools";
}
