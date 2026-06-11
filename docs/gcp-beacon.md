# gcp-beacon — provisioning & ops

Self-hosted ntfy push host (`beacon.rocketware.io`), Caddy-fronted, on a GCP e2-micro.
Config: `hosts/gcp-beacon/`; wrappers: `scripts/gcp-beacon/`.
**Build & deploy run on nixbox** (`ssh -A nixbox`), not the Mac.

## Provision (one-time)

```bash
# Pre-flight (no spend)
nix flake check ~/nixfiles
nixos-rebuild build --flake ~/nixfiles#gcp-beacon          # on nixbox

# GCP setup
gcloud auth login && gcloud config set project rocketware
gcloud services enable compute.googleapis.com
gcloud storage buckets create gs://rocketware-nixos-images --location=us-central1
gcloud compute addresses create gcp-beacon-ip --region=us-central1

# DNS: point beacon.rocketware.io A → the static IP at the registrar.
# Must resolve BEFORE the instance boots (Caddy runs ACME at first boot).
dig +short beacon.rocketware.io

# Image (on nixbox)
IMG=gcp-beacon-$(date +%Y%m%d)
bash scripts/gcp-beacon/build-image.sh
gcloud storage cp result/nixos-image-*.raw.tar.gz gs://rocketware-nixos-images/$IMG.tar.gz
gcloud compute images create $IMG --source-uri=gs://rocketware-nixos-images/$IMG.tar.gz --family=gcp-beacon

# Firewall + instance
gcloud compute firewall-rules create gcp-beacon-web --allow=tcp:80,tcp:443 --source-ranges=0.0.0.0/0 --target-tags=gcp-beacon
gcloud compute firewall-rules create gcp-beacon-ssh --allow=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=gcp-beacon
gcloud compute instances create gcp-beacon --image-family=gcp-beacon --machine-type=e2-micro \
  --zone=us-central1-a --boot-disk-size=30GB --boot-disk-type=pd-standard --address=gcp-beacon-ip --tags=gcp-beacon
```

Break-glass if SSH fails: `gcloud compute ssh gcp-beacon`.

## ntfy auth (one-time, SSH in as jimmyff)

Each topic needs **both** a publisher-write and an owner-read grant (deny-all default).

```bash
sudo ntfy user add owner     && sudo ntfy access owner     'osdn-*' ro
sudo ntfy user add publisher && sudo ntfy access publisher 'osdn-*' wo
sudo ntfy token add publisher        # copy tk_… → Secret Manager for Track B:
gcloud secrets create ntfy-osdn-token --project=<osdn-gcp-project>
printf '%s' "$TOKEN" | gcloud secrets versions add ntfy-osdn-token --data-file=- --project=<osdn-gcp-project>
```

Phone: ntfy Android → server `beacon.rocketware.io`, topics `osdn-sales|alerts|overview`, owner creds; exempt from battery optimisation.

## Smoke test

```bash
curl -H "Authorization: Bearer tk_…" -d hello https://beacon.rocketware.io/osdn-sales   # phone buzzes
```

## Ops

- **Deploy:** `scripts/gcp-beacon/deploy.sh` (from nixbox).
- **Snapshots:** daily boot-disk schedule (holds `user.db` + certs):
  ```bash
  gcloud compute resource-policies create snapshot-schedule gcp-beacon-daily --region=us-central1 --daily-schedule --start-time=04:00 --max-retention-days=7
  gcloud compute disks add-resource-policies gcp-beacon --resource-policies=gcp-beacon-daily --zone=us-central1-a
  ```
- **Restore:** create disk from snapshot → attach as boot disk → start (static IP survives).
