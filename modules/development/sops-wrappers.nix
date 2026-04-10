# On-demand sops wrappers for development secrets.
#
# Wrapper definitions live in sops-wrappers-registry.nix (shared with
# kiln/lib.nix for container/devShell use). This module installs them as
# system packages and bootstraps the sops age identity from the user's
# SSH key on first rebuild.
{
  pkgs-stable,
  lib,
  config,
  username,
  nixfiles-vault,
  ...
}: let
  homeDir =
    if pkgs-stable.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  userGroup =
    if pkgs-stable.stdenv.isDarwin
    then "staff"
    else "users";

  wrappers = import ./sops-wrappers-registry.nix {
    pkgs = pkgs-stable;
    nixfilesVault = nixfiles-vault;
  };

in {
  config = lib.mkIf config.development.enable {
    environment.systemPackages = [
      wrappers.rocketware-android-sign
      wrappers.rocketware-minisign
      wrappers.rocketware-apple-notarize
      wrappers.rocketware-apple-sign
    ];

    # Bootstrap sops age identity from the user's SSH key on first rebuild.
    # Must extend the canonical `postActivation` script: nix-darwin silently
    # drops custom activationScripts names. Runs as root, so the file is
    # chowned to the user afterwards. Parent dirs are chowned too in case
    # .config didn't already exist.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      SSH_KEY="${homeDir}/.ssh/id_ed25519"
      SOPS_DIR="${homeDir}/.config/sops"
      SOPS_AGE_DIR="$SOPS_DIR/age"
      SOPS_KEY_FILE="$SOPS_AGE_DIR/keys.txt"

      if [ ! -f "$SOPS_KEY_FILE" ]; then
        if [ -f "$SSH_KEY" ]; then
          mkdir -p "$SOPS_AGE_DIR"
          if ${pkgs-stable.ssh-to-age}/bin/ssh-to-age -private-key -i "$SSH_KEY" > "$SOPS_KEY_FILE" 2>/dev/null; then
            chmod 600 "$SOPS_KEY_FILE"
            chown ${username}:${userGroup} "$SOPS_KEY_FILE"
            chown ${username}:${userGroup} "$SOPS_AGE_DIR" 2>/dev/null || true
            chown ${username}:${userGroup} "$SOPS_DIR" 2>/dev/null || true
            echo "🔐 Bootstrapped sops age identity at $SOPS_KEY_FILE"
          else
            rm -f "$SOPS_KEY_FILE"
            echo "⚠️  Failed to derive sops age identity from $SSH_KEY"
            echo "    The SSH key may be passphrase-protected; sops requires an unencrypted key."
            echo "    Run manually: ssh-to-age -private-key -i $SSH_KEY > $SOPS_KEY_FILE && chmod 600 $SOPS_KEY_FILE"
          fi
        else
          echo "⚠️  Skipping sops bootstrap: $SSH_KEY not found"
        fi
      fi
    '';
  };
}
