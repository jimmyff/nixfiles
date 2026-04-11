# Kiln

Nix-flake-defined build environment for Flutter apps. Produces Docker images
(Linux/Android CI) and dev shells (macOS) with identical invocation shape.
The same flake runs identically locally and in cloud CI.

## Usage

```nix
kilnLinux = nixfiles.lib.mkKiln {
  project = "cache";
  system  = "x86_64-linux";
  base    = "linux-x86";        # or "macos"
  pkgs    = pkgsLinux;
  version = self.shortRev or "dev";
  targets = [ "linux" "android" ];
  androidSdkPackages = sdk: with sdk; [ cmdline-tools-latest build-tools-35-0-0 ];
  extraPackages = with pkgsLinux; [ nfpm libgit2 ];
  sopsWrappers = [ "rocketware-android-sign" "rocketware-minisign" ];
};
```

## Return value

| Field | Type | Description |
|-------|------|-------------|
| `entrypoint` | derivation | `writeShellScriptBin "kiln-entrypoint"` — shared by Docker + devShell |
| `packages` | list | Full resolved package list |
| `env` | attrset | Merged environment variables |
| `dockerImage` | derivation/null | `streamLayeredImage` (null for macos base) |
| `loadScript` | derivation/null | Pipes image stream to `docker load` |
| `pushScript` | derivation/null | Pipes image stream to `skopeo copy → $KILN_REGISTRY` |
| `devShell` | derivation | `mkShell` (linux) or `mkShellNoCC` (macos) |
| `meta` | attrset | `{ project; version; base; system; targets; imageName; imageTag; }` |

## Entrypoint contract

Identical behavior in Docker and dev shell:

1. **Workspace**: if `/workspace` exists and is non-empty, `cd` into it
2. **Age key**: `SOPS_AGE_KEY` > `SOPS_AGE_KEY_FILE` > `~/.config/sops/age/keys.txt`
3. **Flutter shim**: if `FLUTTER_ROOT` is in `/nix/store`, rsyncs to `/tmp/flutter-writable` (writable copy with framework symlinks preserved)
4. **Arguments**: strips leading `--`, then `exec "$@"` (or `defaultCommand` if no args)

## Sops wrappers

Pass strings for known wrappers or derivations for custom ones:

```nix
sopsWrappers = [ "rocketware-android-sign" customWrapperDrv ];
```

Known names: `rocketware-android-sign`, `rocketware-minisign`,
`rocketware-apple-notarize`, `rocketware-apple-sign`.

## Parameters

See `lib.nix` for the full function signature with all parameters and defaults.
