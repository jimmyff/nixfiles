# restore — vault backups

`~/data/vault` is snapshotted hourly to an encrypted restic repository on Koofr. Config: `modules/services/restic.nix`.

restic encrypts client-side, so the repository targets the plain `koofr-raw:` remote rather than the `koofr:` crypt layer — one password in the restore path, not two. That password is kept offline, deliberately out of version control.

```bash
nix shell nixpkgs#restic nixpkgs#rclone
export RESTIC_REPOSITORY="rclone:koofr-raw:restic-vault"

restic snapshots                                    # list what is available
restic restore latest --target /tmp/vault-restore   # scratch path, never over live data
restic check                                        # verify repository integrity
```

Retention is 7 daily, 4 weekly and 12 monthly, grouped by host and path. Only one host prunes — concurrent prunes contend for the repository lock.
