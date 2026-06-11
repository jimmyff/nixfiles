# gcp-beacon — image build & deploy

Repeatable wrappers for the Rocketware ntfy push host (`gcp-beacon`). One-time provisioning,
bootstrap, and DR/ops live in [`docs/gcp-beacon.md`](../../docs/gcp-beacon.md).

## Where to run

**On nixbox** (`ssh -A nixbox`), not the Mac:

- The Mac (aarch64-darwin) has no Linux builder; the e2-micro would OOM evaluating the flake.
- Agent forwarding (`-A`) is needed for the private `nixfiles-vault` fetch.

The scripts guard for this and exit early elsewhere. They are invoked by path (not on `$PATH`).

## Workflow (Mac → nixbox)

```bash
ssh -A nixbox
cd ~/nixfiles

# First time / disaster recovery: build the GCE image, then upload (see docs step 4)
bash scripts/gcp-beacon/build-image.sh

# Steady state: push a config change to the running host
bash scripts/gcp-beacon/deploy.sh
```

## Artifacts

- `build-image.sh` → `result/nixos-image-*.raw.tar.gz` (native `system.build.googleComputeImage`,
  pinned by `flake.lock`).
- `deploy.sh [target]` → `nixos-rebuild switch --target-host` (defaults to
  `jimmyff@beacon.rocketware.io`; pass an IP for the pre-DNS first touch).
