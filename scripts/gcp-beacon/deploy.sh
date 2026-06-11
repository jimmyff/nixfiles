#!/usr/bin/env bash
# Push the current gcp-beacon config to the running host (steady-state deploy).
# Run on nixbox. Deploys as jimmyff with remote sudo — root SSH is disabled by house policy;
# the baked image carries jimmyff's key + passwordless wheel.
#
# Usage:
#   ssh -A nixbox
#   bash scripts/gcp-beacon/deploy.sh [target]
#
# [target] defaults to jimmyff@beacon.rocketware.io. Pass an IP for the pre-DNS first touch:
#   bash scripts/gcp-beacon/deploy.sh jimmyff@34.x.x.x

set -euo pipefail

[[ "$(uname -sm)" == "Linux x86_64" ]] || { echo "run on nixbox (ssh -A nixbox — agent needed for nixfiles-vault)"; exit 1; }

TARGET="${1:-jimmyff@beacon.rocketware.io}"

echo ">>> Deploying gcp-beacon config to ${TARGET}..."
nixos-rebuild switch --flake "$HOME/nixfiles#gcp-beacon" --target-host "$TARGET" --sudo

echo ""
echo "=== Deploy complete ==="
echo "Check: ssh ${TARGET} 'systemctl status ntfy-sh caddy'"
