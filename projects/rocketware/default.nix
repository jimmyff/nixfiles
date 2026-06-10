{
  pkgs,
  lib,
}: {
  # Repository information
  repo = "git@github.com:jimmyff/rocketware-super.git";

  # Required packages for this project
  packages = with pkgs; [
  ];

  # Development scripts to include
  scripts = {
    global = [];
    local = [];
  };

  # Project description
  description = "Rocketware - super repository workspace";
}
