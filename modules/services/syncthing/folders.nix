# Synced folders. A folder lives at $SYNC_ROOT/<id> on every host that names it.
# Device IDs are in the vault (`syncthing-devices.nix`), keyed by the same hostnames.
#
#   hosts           hostnames carrying the folder
#   label           shown in the Syncthing UI
#   paths.<host>    absolute path override, for data that already lives somewhere
#   types.<host>    sendreceive (default) | sendonly | receiveonly
#   versioning      keeps changed/deleted files: https://docs.syncthing.net/users/versioning.html
#   ignorePatterns  .stignore lines (NixOS hosts only)
{
  # Kosmos working data: cache/ (dev corpus + LLM spend cache) and art/ (curated assets).
  kosmos_data = {
    label = "Kosmos data";
    hosts = [ "jimmyff-mbp14" "nixbox" "nasbox" ];
    versioning = {
      type = "trashcan";
      params.cleanoutDays = "30";
    };
  };
}
