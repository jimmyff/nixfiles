{ lib, config, pkgs-stable, username, ... }:
let
  cfg = config.minisign;
  homeDir =
    if pkgs-stable.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";
  userGroup =
    if pkgs-stable.stdenv.isDarwin
    then "staff"
    else "users";
in {
  options.minisign = {
    enable = lib.mkEnableOption "Minisign release signing";
  };

  config = lib.mkIf cfg.enable {
    # Signing key moved to sops — materialised on demand by the
    # `rocketware-minisign` wrapper. See modules/development/rocketware-secrets.nix.
    # Public key still deployed directly below (not a secret).
    system.activationScripts.minisignPublicKey = {
      text = ''
        mkdir -p ${homeDir}/.minisign
        cat > ${homeDir}/.minisign/minisign-rocketware.pub << 'EOF'
untrusted comment: minisign public key 5CFCEFF7AD20C8AE
RWSuyCCt9+/8XP0AK3jidFQotJmj82u3RQvmTRCHZeW460xcSsjxH8RQ
EOF
        chown ${username}:${userGroup} ${homeDir}/.minisign/minisign-rocketware.pub
        chmod 644 ${homeDir}/.minisign/minisign-rocketware.pub
      '';
    };
  };
}
