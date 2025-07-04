{ config, pkgs, lib, inputs, username, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  networking.hostName = "nixelbook";

 
}
