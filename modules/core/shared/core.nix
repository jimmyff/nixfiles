{ pkgs-stable, pkgs-dev-tools, inputs, ... }:
let
  agenixPkg = inputs.agenix.packages.${pkgs-stable.stdenv.hostPlatform.system}.default;

  # agenix searches SSH identities only, but the universal recipient in
  # secrets.nix is a native age key (age1…) kept in the sops keys file. Without
  # it, any secret not granted to this host's SSH key fails to decrypt — and
  # `agenix -r` fails *partway*, leaving the vault half-rekeyed with nothing to
  # say which files were missed. Passing it always removes that footgun.
  agenix = pkgs-stable.writeShellScriptBin "agenix" ''
    KEY="$HOME/.config/sops/age/keys.txt"
    if [ -f "$KEY" ]; then
      exec ${agenixPkg}/bin/agenix -i "$KEY" "$@"
    else
      exec ${agenixPkg}/bin/agenix "$@"
    fi
  '';
in
{

  nix.enable = true;
  nix.package = pkgs-stable.nix;
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.allowed-users = [ "@wheel" ];

  # crates.io 403s any User-Agent starting with "curl/", which is exactly what
  # nixpkgs' fetchurl sends (`--user-agent "curl/$ver Nixpkgs/$ver"`), breaking
  # every Rust crate fetch that isn't already cached. NIX_CURL_FLAGS is appended
  # after that flag, and curl honours the last occurrence. Remove once fixed
  # upstream.
  nix.envVars.NIX_CURL_FLAGS = "--user-agent Nixpkgs";

  # Timezone
  time.timeZone = "Europe/London";


  environment.systemPackages = [
    pkgs-stable.age                      # Encryption library
    agenix                               # Age nix secrets tool (wrapped, see above)
    pkgs-stable.bat                      # Cat clone with syntax highlighting
    pkgs-stable.jq                       # JSON processor; the git clean filters need it
    pkgs-stable.minisign                  # Release signing tool
    pkgs-stable.vim                      # Vi/Vim text editor

    # GNU `timeout` only (missing from macOS BSD base), without
    # shadowing the BSD coreutils (ls/cp/date/...) in PATH.
    (pkgs-stable.runCommand "timeout" { } ''
      mkdir -p $out/bin
      ln -s ${pkgs-stable.coreutils}/bin/timeout $out/bin/timeout
    '')
  ];

  environment.shells = [ pkgs-stable.bash pkgs-stable.zsh pkgs-dev-tools.nushell ];

}