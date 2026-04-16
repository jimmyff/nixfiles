#!/usr/bin/env bash
# NixOS Bootstrap - Phase 2: Setup
# Run this after first boot, as the jimmyff user (via SSH with agent forwarding)
#
# Usage: ssh -A jimmyff@<ip>
#        bash bootstrap-setup.sh <hostname>
#
# Example:
#        bash bootstrap-setup.sh nixbox

set -euo pipefail

HOSTNAME="${1:?Usage: bootstrap-setup.sh <hostname>}"
NIXFILES_REPO="git@github.com:jimmyff/nixfiles.git"
NIXFILES_DIR="${HOME}/nixfiles"

echo "=== NixOS Bootstrap Phase 2: ${HOSTNAME} ==="

# Validate hostname early (will also check against repo after clone)
VALID_HOSTNAMES="nixelbook nixbox nasbox"
if ! echo "${VALID_HOSTNAMES}" | grep -qw "${HOSTNAME}"; then
  echo "ERROR: Unknown hostname '${HOSTNAME}'"
  echo "Valid hostnames: ${VALID_HOSTNAMES}"
  exit 1
fi

# Verify SSH agent forwarding
echo ">>> Checking SSH agent forwarding..."
SSH_RESULT=$(ssh -T git@github.com 2>&1 || true)
if ! echo "${SSH_RESULT}" | grep -q "successfully authenticated"; then
  echo "ERROR: SSH agent forwarding not working."
  echo "Reconnect with: ssh -A jimmyff@<ip>"
  exit 1
fi
echo "SSH agent forwarding OK"

# Clone nixfiles
if [ -d "${NIXFILES_DIR}" ]; then
  echo ">>> nixfiles already exists, pulling latest..."
  cd "${NIXFILES_DIR}"
  git pull
else
  echo ">>> Cloning nixfiles..."
  git clone "${NIXFILES_REPO}" "${NIXFILES_DIR}"
fi

# Validate hostname exists in flake
if [ ! -d "${NIXFILES_DIR}/hosts/${HOSTNAME}" ]; then
  echo "ERROR: No host configuration found for '${HOSTNAME}'"
  echo "Available hosts:"
  ls "${NIXFILES_DIR}/hosts/"
  exit 1
fi

# Rebuild system
echo ">>> Rebuilding NixOS as ${HOSTNAME}..."
cd "${NIXFILES_DIR}"
sudo nixos-rebuild switch --flake ".#${HOSTNAME}"

echo ""
echo "=== Phase 2 complete ==="
echo ""
echo "System rebuilt as ${HOSTNAME}."
echo "You may need to log out and back in for shell changes to take effect."
echo ""
if command -v dev-setup &>/dev/null; then
  echo "Development environment detected. Run 'dev-setup' to set up projects."
fi
