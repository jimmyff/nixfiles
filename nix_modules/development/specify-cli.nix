{
  inputs,
  pkgs-dev-tools,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.specify-cli;

  # Cross-platform home directory
  homeDir =
    if pkgs-dev-tools.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # XDG paths
  xdgDataHome =
    if pkgs-dev-tools.stdenv.isDarwin
    then "${homeDir}/.local/share"
    else "${homeDir}/.local/share";

  # Cross-platform user group
  userGroup =
    if pkgs-dev-tools.stdenv.isDarwin
    then "staff"
    else "users";
in {
  options.specify-cli = {
    enable = lib.mkEnableOption "specify-cli development tool from GitHub's spec-kit";
  };

  config = lib.mkIf cfg.enable {
    # Setup specify-cli via uv tool install
    system.activationScripts.specifyCli = {
      text = ''
        # Install specify-cli using uv
        if command -v uv >/dev/null 2>&1; then
          echo "📦 Installing specify-cli from GitHub spec-kit..."

          # Run as the user, not as root
          su - ${username} -c "uv tool install specify-cli --from git+https://github.com/github/spec-kit.git" || echo "Warning: Failed to install specify-cli"

          echo "✅ Activated specify-cli development tool"
        else
          echo "⚠️  UV not found, skipping specify-cli installation"
        fi
      '';
      deps = ["users" "groups"];
    };
  };
}
