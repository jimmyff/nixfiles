{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/virtualisation/google-compute-image.nix") ];
  nixpkgs.hostPlatform = "x86_64-linux";
}
