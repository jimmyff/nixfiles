# rclone-sync

One-way sync for rclone remotes.

## Usage

```bash
cd ~/Cloud/Apps
rclone-sync --push    # local → cloud (upload)
rclone-sync --pull    # cloud → local (download)
```

## Options

- `--push` - Upload local changes to cloud
- `--pull` - Download cloud changes to local
- `--skip-dry-run` - Skip dry run, sync immediately
- `[remote]` - Remote name (default: "default")

## Behavior

1. Validates cwd is under `~/Cloud/`
2. Runs dry-run showing proposed changes
3. Prompts for confirmation
4. Syncs in specified direction
