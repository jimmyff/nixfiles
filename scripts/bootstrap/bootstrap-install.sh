#!/usr/bin/env bash
# NixOS Bootstrap - Phase 1: Install
# Run from the NixOS minimal live ISO (UEFI or BIOS)
#
# Usage:
#   sudo bash bootstrap-install.sh <hostname> <ssh-public-key> [--bios] [--disk /dev/sdX]
#
# Examples:
#   sudo bash bootstrap-install.sh nixbox "ssh-ed25519 AAAA... jimmy@mbp"
#   sudo bash bootstrap-install.sh nixbox "ssh-ed25519 AAAA... jimmy@mbp" --bios
#   sudo bash bootstrap-install.sh nixbox "ssh-ed25519 AAAA... jimmy@mbp" --disk /dev/vda

set -euo pipefail

# --- Defaults ---
BOOT_MODE="uefi"
DISK="/dev/sda"
USERNAME="jimmyff"
VALID_HOSTNAMES="nixelbook nixbox nasbox"

usage() {
  echo "Usage: bootstrap-install.sh <hostname> <ssh-public-key> [--bios] [--disk /dev/sdX]"
  echo ""
  echo "Valid hostnames: ${VALID_HOSTNAMES}"
  exit 1
}

# --- Required positional args ---
HOSTNAME="${1:?$(usage)}"
shift
SSH_PUBKEY="${1:?$(usage)}"
shift

# --- Optional flags ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bios) BOOT_MODE="bios"; shift ;;
    --disk) DISK="${2:?--disk requires a device path (e.g. /dev/vda)}"; shift 2 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# --- Validate hostname ---
if ! echo "${VALID_HOSTNAMES}" | grep -qw "${HOSTNAME}"; then
  echo "ERROR: Unknown hostname '${HOSTNAME}'"
  echo "Valid hostnames: ${VALID_HOSTNAMES}"
  exit 1
fi

# --- Verify disk ---
if [ ! -b "${DISK}" ]; then
  echo "ERROR: Disk '${DISK}' not found or is not a block device."
  echo "Available disks:"
  lsblk -d -o NAME,SIZE,TYPE | grep disk
  exit 1
fi

# --- Confirm before erasing ---
echo "=== NixOS Bootstrap: ${HOSTNAME} ==="
echo "Disk:      ${DISK}"
echo "Boot mode: ${BOOT_MODE}"
echo "User:      ${USERNAME}"
echo ""
echo "WARNING: This will ERASE ALL DATA on ${DISK}."
echo ""
read -p "Continue? (type 'yes' to proceed): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
  echo "Aborted."
  exit 0
fi
echo ""

# Partition
echo ">>> Partitioning ${DISK}..."
if [ "${BOOT_MODE}" = "uefi" ]; then
  parted "${DISK}" -- mklabel gpt
  parted "${DISK}" -- mkpart root ext4 512MB 100%
  parted "${DISK}" -- mkpart ESP fat32 1MB 512MB
  parted "${DISK}" -- set 2 esp on

  mkfs.ext4 -L nixos "${DISK}1"
  mkfs.fat -F 32 -n boot "${DISK}2"

  udevadm settle
  mount /dev/disk/by-label/nixos /mnt
  mkdir -p /mnt/boot
  mount /dev/disk/by-label/boot /mnt/boot
else
  parted "${DISK}" -- mklabel msdos
  parted "${DISK}" -- mkpart primary ext4 1MB 100%
  parted "${DISK}" -- set 1 boot on

  mkfs.ext4 -L nixos "${DISK}1"

  udevadm settle
  mount /dev/disk/by-label/nixos /mnt
fi

# Generate hardware config
echo ">>> Generating hardware configuration..."
nixos-generate-config --root /mnt

# Bootloader config
if [ "${BOOT_MODE}" = "uefi" ]; then
  BOOTLOADER='boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;'
else
  BOOTLOADER="boot.loader.grub.enable = true;
  boot.loader.grub.device = \"${DISK}\";"
fi

# Write minimal bootstrap configuration for first boot
# NOTE: Heredoc is deliberately unquoted so bash expands ${...} variables
cat > /mnt/etc/nixos/configuration.nix << NIXCFG
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  ${BOOTLOADER}

  networking.hostName = "${HOSTNAME}";
  networking.useDHCP = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  users.users.${USERNAME} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "${SSH_PUBKEY}" ];
  };

  # Allow wheel group to sudo without password (for bootstrap)
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [ git vim ];

  system.stateVersion = "25.11";
}
NIXCFG

echo ">>> Installing NixOS..."
nixos-install --no-root-passwd

echo ""
echo "=== Phase 1 complete ==="
echo "Reboot, then SSH in:"
echo "  ssh -A ${USERNAME}@<ip>"
echo ""
echo "Then run Phase 2 (copy bootstrap-setup.sh to the host):"
echo "  bash bootstrap-setup.sh ${HOSTNAME}"
