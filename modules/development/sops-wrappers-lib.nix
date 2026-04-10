# mkSopsWrapper — generic helper for sops-backed secret wrappers.
#
# Produces a writeShellScriptBin that materialises encrypted secrets into
# an ephemeral tempdir, exports env vars, and runs a child command. Two
# modes: standard template (simple wrappers) and body override (complex
# multi-mode wrappers that manage their own tempdir/decrypt logic).
#
# The shared preamble (always generated) handles:
#   - set -euo pipefail
#   - SOPS / VAULT variable setup
#   - 3-tier age identity resolution (SOPS_AGE_KEY > SOPS_AGE_KEY_FILE > file)
#   - require_file() helper
{
  name,
  description ? "",
  sopsFiles ? {},
  envFiles ? [],
  envVarsAfterDecrypt ? {},
  preRun ? "",
  postRun ? "",
  body ? null,
  pkgs,
  nixfilesVault,
}:
let
  lib = pkgs.lib;
  sopsBin = "${pkgs.sops}/bin/sops";

  preamble = ''
    set -euo pipefail

    SOPS=${sopsBin}
    VAULT=${nixfilesVault}

    # Age identity resolution: SOPS_AGE_KEY > SOPS_AGE_KEY_FILE > ~/.config/sops/age/keys.txt
    if [ -n "''${SOPS_AGE_KEY:-}" ]; then
      : # sops honours SOPS_AGE_KEY directly
    elif [ -n "''${SOPS_AGE_KEY_FILE:-}" ]; then
      : # sops honours SOPS_AGE_KEY_FILE directly
    elif [ -r "$HOME/.config/sops/age/keys.txt" ]; then
      : # sops will find this on its own
    else
      echo "ERROR: no sops identity found." >&2
      echo "       Set SOPS_AGE_KEY (raw key), SOPS_AGE_KEY_FILE (path)," >&2
      echo "       or run a system rebuild to bootstrap ~/.config/sops/age/keys.txt." >&2
      exit 1
    fi

    require_file() {
      if [ ! -f "$1" ]; then
        echo "ERROR: required sops file missing: $1" >&2
        echo "       The nixfiles-vault flake input may be stale." >&2
        echo "       Run: nix flake update nixfiles-vault && rebuild your system" >&2
        exit 1
      fi
    }
  '';

  # --- Standard template (body == null) ---

  hasBinaryFiles = sopsFiles != {};

  # Pre-flight checks for encrypted files
  preflightChecks = let
    binaryChecks = lib.concatStringsSep "\n" (lib.mapAttrsToList
      (_: vaultRelPath: ''require_file "$VAULT/${vaultRelPath}"'')
      sopsFiles);
    envChecks = lib.concatStringsSep "\n"
      (map (f: ''require_file "$VAULT/${f}"'') envFiles);
  in
    lib.optionalString (binaryChecks != "") binaryChecks
    + lib.optionalString (binaryChecks != "" && envChecks != "") "\n"
    + lib.optionalString (envChecks != "") envChecks;

  # Decrypt binary files into tempdir
  decryptCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (logicalName: vaultRelPath: ''
      "$SOPS" --decrypt --input-type binary --output-type binary \
        --output "$TMPDIR_KS/${logicalName}" "$VAULT/${vaultRelPath}"
      chmod 600 "$TMPDIR_KS/${logicalName}"'')
    sopsFiles);

  # Export env vars pointing at decrypted files
  envExports = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (envVar: logicalName: ''export ${envVar}="$TMPDIR_KS/${logicalName}"'')
    envVarsAfterDecrypt);

  # Build command execution (with optional sops exec-env)
  execBlock = if envFiles == [] then ''
    eval $quoted_cmd
  '' else
    # Standard template only supports a single envFile
    assert lib.assertMsg (builtins.length envFiles <= 1)
      "mkSopsWrapper standard template supports at most 1 envFile; use body override for multiple";
    let envFile = builtins.head envFiles;
    in ''
      "$SOPS" exec-env "$VAULT/${envFile}" "$quoted_cmd"
    '';

  templateBody = ''
    usage() {
      cat >&2 <<'USAGE'
    Usage: ${name} -- <command> [args...]

    ${description}
    USAGE
      exit 64
    }

    [ "''${1:-}" = "--" ] || usage
    shift
    [ $# -ge 1 ] || usage

    ${preflightChecks}
  '' + (if hasBinaryFiles then ''

    TMPDIR_KS=$(mktemp -d -t ${name}-XXXXXXXX)
    trap '${postRun}rm -rf -- "$TMPDIR_KS"' EXIT

    ${decryptCommands}
    ${envExports}
  '' else
    lib.optionalString (postRun != "") ''

    trap '${postRun}' EXIT
  '') + ''

    ${preRun}
    quoted_cmd=$(printf '%q ' "$@")
    ${execBlock}
  '';

in
pkgs.writeShellScriptBin name (
  if body != null
  then preamble + body
  else preamble + templateBody
)
