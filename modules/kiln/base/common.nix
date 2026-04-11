# Shared cross-platform CLI packages and environment variables.
# Imported by sibling base modules (linux-x86.nix, macos.nix).
{ pkgs }:
{
  coreCliPackages = with pkgs; [
    bashInteractive coreutils findutils gnugrep gnused gawk
    gnutar gzip xz
    curl wget cacert rsync
    git gh openssh
    sops age
    nushell jq which
  ];

  # Base environment variables (cross-platform).
  # Note: PUB_CACHE, GRADLE_USER_HOME, FLUTTER_GRADLE_PLUGIN_BUILDDIR, TZ
  # are set by lib.nix's ephemeralEnv (higher precedence) — not duplicated here.
  coreCliEnv = {
    LANG = "C.UTF-8";
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };
}
