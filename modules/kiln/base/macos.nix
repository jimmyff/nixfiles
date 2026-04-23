# macOS (aarch64-darwin) base module for mkKiln.
# Produces a dev shell only — no Docker image (macOS can't be containerized).
# Xcode is assumed pre-installed on the host (Command Line Tools or Xcode.app).
{ pkgs, inputs }:
let
  common = import ./common.nix { inherit pkgs; };
in
{
  system = "aarch64-darwin";
  label = "macos";

  corePackages = common.coreCliPackages ++ (with pkgs; [
    # iOS/macOS Flutter builds need CocoaPods
    cocoapods

    # Build toolchain (native plugin compilation — parity with linux-x86 base)
    cmake pkg-config
  ]);

  baseEnv = common.coreCliEnv;

  layerGroups = {};
}
