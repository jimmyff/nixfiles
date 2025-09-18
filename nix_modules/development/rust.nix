{
  inputs,
  pkgs,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.rust;

  # Cross-platform home directory
  homeDir =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # Cross-platform user group
  userGroup =
    if pkgs.stdenv.isDarwin
    then "staff"
    else "users";
in {
  options.rust = {
    enable = lib.mkEnableOption "Rust development environment";
  };

  config = lib.mkIf cfg.enable {
    # Rust development packages
    environment.systemPackages = with pkgs; [
      cargo
      rustc
      rust-analyzer
      rust-script
    ];

    # Rust environment variables (XDG compliant)
    environment.variables = {
      CARGO_HOME = "${homeDir}/.local/share/cargo";
    };

    # Setup Rust directories
    system.activationScripts.rustSetup = {
      text = ''
        echo "Setting up Rust development environment..."

        # Create Rust directories (XDG compliant)
        mkdir -p ${homeDir}/.local/share/cargo/bin

        # Set ownership
        chown -R ${username}:${userGroup} ${homeDir}/.local/share/cargo 2>/dev/null || echo "Warning: Could not set ownership of Rust cargo directory"

        echo "Rust development environment setup complete!"
      '';
      deps = ["users" "groups"];
    };
  };
}