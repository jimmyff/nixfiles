# Remote development — tailnet + nixbox

The laptop is a thin client; the herdr hub, Flutter toolchain and builds live on nixbox. Every host joins one Tailscale tailnet (`modules/services/tailscale.nix`), so the home IP and port-forwarding never matter.

## Tailnet

| Host | Enrolment |
| ---- | --------- |
| NixOS hosts | `tailscale.enable = true`, then `sudo tailscale up` once after the rebuild |
| macOS | same via nix-darwin, then `sudo tailscale set --operator=$USER` |
| Proxmox host | outside nix: Tailscale's install script, then `tailscale up` — keeps the VM console reachable |
| Phone | the Tailscale app, same account |

The ssh aliases (`home/shared/services/ssh.nix`) proxy through `tailscale nc`, so `ssh nixbox` works on any network with any local resolver. Linux hosts grant the user as operator, so the CLI needs no sudo.

## The hub on nixbox

```shell
mux --remote nixbox            # attach nixbox's hub (creates it the first time)
mux --remote nixbox kosmos     # pin kosmos there first, then attach
ssh nixbox mux unpin kosmos    # curation runs on the host
```

herdr keeps the TUI local (chords, sidebar, kanata layers unchanged) and reconnects the ssh transport after wifi drops or lid-close. Agents keep running on nixbox while detached. Rebuild nixbox before the clients: herdr's remote setup wants matching server and client versions, and the store binary can't be swapped in place.

## Testing Flutter apps

- **Web:** on nixbox `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080`, then open `http://nixbox:8080` from the laptop. `r` hot-reloads. The Chrome device target needs a local browser.
- **Android:** phone on the tailnet with *Wireless debugging* on. From nixbox: `adb pair <phone>:<pair-port>` once, then `adb connect <phone>:<port>` and `flutter run -d <id>`. Hot reload works because adb and the VM-service forward both live on nixbox. Android re-randomises the port whenever wireless debugging toggles.
- **Fallback:** build the APK on nixbox, copy it over, `adb install` with the `android-tools` package.
- **Linux desktop:** on the laptop keep `waypiper nixbox` running, then on nixbox `waypiper run flutter run -d linux`. The window opens on the laptop; nixbox renders on the CPU. A dropped link closes the app; waypiper reconnects, so just rerun.

## Rebuilding nixelbook without local disk

```shell
nixos-rebuild switch --flake ~/nixfiles#nixelbook --build-host nixbox --sudo
```

Evaluates locally, builds on nixbox, copies the closure back. Run as the user, not under `sudo` — root has no ssh keys or aliases. `sudo nix-collect-garbage -d` first if space is tight.

## Before leaving

1. Proxmox: VMs set to start on boot; Tailscale on the host.
2. Rebuild nixbox, then the clients; enrol each; `tailscale status` lists every peer.
3. Rehearse off-LAN (phone hotspot): `ssh nixbox`, `mux --remote nixbox`, web reload, phone reload.
