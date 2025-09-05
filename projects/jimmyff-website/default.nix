{ pkgs, lib }:

{
  # Repository information
  repo = "https://github.com/jimmyff/jimmyff-website.git";
  
  # Required packages for this project
  packages = with pkgs; [
    zola
    git-lfs
  ];
  
  # Development scripts to include
  scripts = {
    global = ["git-manager/gm.nu"];
    local = [];
  };
  
  # Project description
  description = "Jimmy's personal website built with Zola";
}