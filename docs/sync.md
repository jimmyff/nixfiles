# sync — Syncthing folders

Peer-to-peer folder sync between hosts, declared in `modules/services/syncthing/`. Every subscribed host holds a full local copy, so work is offline-capable and no host depends on another. An always-on peer carries changes between machines whose uptime doesn't overlap.

| Where | Holds |
| ----- | ----- |
| `folders.nix` | folder id → label, hosts, optional path/type overrides, versioning, ignores |
| vault `syncthing-devices.nix` | hostname → device ID; identifiers, so kept out of the public repo |

A host enables with `syncthing.enable = true` and receives every folder in the registry that names it. Folders live at `$SYNC_ROOT/<folder-id>` — `~/sync` by default, `syncthing.syncRoot` to move it — unless the registry overrides the path. Projects reference `$SYNC_ROOT`, never a host-specific path.

## Enrolling a host

Device IDs exist only after the first start, so a new host takes two rebuilds:

1. `syncthing.enable = true`, rebuild. The build warns that the host has no ID; that's expected.
2. On the host: `syncthing cli show system | jq -r .myID`. Add `<hostname> = "<id>";` to the vault file and push it; `nix flake update nixfiles-vault`.
3. Rebuild every host that shares a folder with it. Peers find each other by LAN broadcast; global discovery and relays are off.

The web UI binds to localhost. Headless hosts: `ssh -L 8384:127.0.0.1:8384 <host>`, then `http://127.0.0.1:8384`.

## Adding a folder

Add an entry to `folders.nix`, rebuild the hosts it names. Syncthing creates the directory. Data that already lives at a fixed path uses `paths.<host>`; a backup-style folder marks the receiving side `receiveonly`.

```nix
documents = {
  label = "Documents";
  hosts = [ "laptop" "desktop" "nas" ];
  paths.laptop = "/home/me/Documents";
  types.nas = "receiveonly";
  versioning = { type = "staggered"; params.maxAge = "2592000"; };
};
```

restic already excludes Syncthing's markers (`.stfolder`, `.stversions`), so a synced folder can also be a restic path.

## Conflicts

Two hosts editing the same file before syncing produces a `.sync-conflict-*` copy beside it rather than a merge. Append-only logs written from more than one host should be split per host.
