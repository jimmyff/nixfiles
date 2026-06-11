#!/usr/bin/env bash
# Build the gcp-beacon GCE image — native flake output, fully pinned by flake.lock.
# Run on nixbox: the Mac has no Linux builder, and the build runs in a VM (needs /dev/kvm).
#
# Usage:
#   ssh -A nixbox
#   bash scripts/gcp-beacon/build-image.sh

set -euo pipefail

[[ "$(uname -sm)" == "Linux x86_64" ]] || { echo "run on nixbox (ssh -A nixbox — agent needed for nixfiles-vault)"; exit 1; }

echo ">>> Building gcp-beacon GCE image (evaluates + builds in a VM; needs /dev/kvm)..."
nix build "$HOME/nixfiles#nixosConfigurations.gcp-beacon.config.system.build.googleComputeImage" -o result

echo ""
echo "=== Image built ==="
echo "Artifact: $(ls result/nixos-image-*.raw.tar.gz)"
echo "Next (see docs/gcp-beacon.md step 4):"
echo "  gcloud storage cp result/nixos-image-*.raw.tar.gz gs://rocketware-nixos-images/gcp-beacon-YYYYMMDD.tar.gz"
