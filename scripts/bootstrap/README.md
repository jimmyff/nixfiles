# nixfiles NixOS Bootstrap

Two-phase bootstrap for new NixOS hosts.

## Phase 1: Install (from NixOS live ISO)

```bash
sudo bash bootstrap-install.sh <hostname> "<ssh-public-key>" [--bios] [--disk /dev/sdX]
```

Partitions disk, installs minimal NixOS with SSH access. Defaults to UEFI + `/dev/sda`.

## Phase 2: Setup (after reboot, via SSH)

```bash
ssh -A jimmyff@<ip>
bash bootstrap-setup.sh <hostname>
```

Clones nixfiles, runs `nixos-rebuild switch`. Requires SSH agent forwarding (`-A`).

## Proxmox VM checklist

- BIOS: OVMF (UEFI), Secure Boot **off**
- CPU type: host
- Disk: VirtIO SCSI (`/dev/sda`) or VirtIO Block (`--disk /dev/vda`)
- SSD emulation: on (if backed by SSD)
- QEMU guest agent: enabled in VM options
