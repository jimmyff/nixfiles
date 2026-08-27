let
  # Machines to deploy to. Keys from /etc/ssh/ssh_host_ed25519_key.pub,
  # or the user key on Darwin.
  # Workstations — machines worked on directly.
  workstations = {
    nixelbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB2ECjQ848rCrkkBZ5bKI8lg34fEB9WOwktTDzwhTxnI root@nixos";
    jimmyff-mbp14 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAaZzF+34ChHrzl1Zr3crf60Snog3AQaHCrPNegyDitC jimmyff";
    nixbox = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAMpe7t054td28L7exaDbKsy071XtIvhiQU1k044rdZf root@nasbox"; # remote dev VM;
  };

  # Infrastructure — headless, deliberately narrow grants.
  # No allServers helper on purpose: nasbox is LAN-only, beacon is
  # internet-facing. Their risk profiles differ too much to grant as a group.
  servers = {
    nasbox = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAMpe7t054td28L7exaDbKsy071XtIvhiQU1k044rdZf root@nasbox";

    # Regenerated whenever the instance is recreated from a fresh image —
    # re-key after any rebuild that isn't a snapshot restore.
    gcp-beacon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKVO3UKfwoEMvsi4S5FjB7/e+UYKt+rTkv2Mw0oXVQSf root@gcp-beacon";
  };

  users = {
    # Original yubikey key - commented out but kept for Darwin debugging if needed
    # jimmyff = "age1yubikey1qg8nf40dfw4gprmywplggtg2wuvv55fcmujzrm65z8s3j6rhwje2vm3hhs7";

    # ed25519 SSH key derived age key
    jimmyff = "age1qzs9ac3a9j7rhf6t25hrk5jgaqhhu7mnsnuk4n8fz5hw2603v47s9fztm2";
  };

  allUsers = builtins.attrValues users;
  allWorkstations = builtins.attrValues workstations;

  allServers = builtins.attrValues servers;

  # Every machine. For low-sensitivity config only — never credentials.
  allMachines = allWorkstations ++ allServers;
in {
  # NextDNS config IDs (one per host)
  "nextdns_nixelbook.age".publicKeys = allUsers ++ allMachines;
  "nextdns_mbp14.age".publicKeys = allUsers ++ allMachines;

  # Android signing — kept explicit; widen to allWorkstations if nixbox should build releases
  "android-release-key.jks.age".publicKeys = allUsers ++ [workstations.nixelbook workstations.jimmyff-mbp14];
  "android-debug-keystore.age".publicKeys = allUsers ++ [workstations.nixelbook workstations.jimmyff-mbp14];
  "android-googleplay-upload-key.jks.age".publicKeys = allUsers ++ [workstations.nixelbook workstations.jimmyff-mbp14];

  # rclone — Koofr remote. nasbox targets Drive, not Koofr, so it is excluded.
  "rclone-koofr-user.age".publicKeys = allUsers ++ allWorkstations;
  "rclone-koofr-pass.age".publicKeys = allUsers ++ allWorkstations;

  # rclone — crypt layer, shared by the Koofr and (future) Drive remotes
  "rclone-crypt-pass.age".publicKeys = allUsers ++ allWorkstations ++ [servers.nasbox];
  "rclone-crypt-salt.age".publicKeys = allUsers ++ allWorkstations ++ [servers.nasbox];

  # restic — vault backups run on the laptops only. Excluding nasbox means a
  # compromised NAS cannot read the vault backups, only the archive.
  "restic-password.age".publicKeys = allUsers ++ [workstations.nixelbook workstations.jimmyff-mbp14];

  # Minisign — likely stale; minisign.nix says the signing key moved to sops
  "minisign-rocketware-signing-key.age".publicKeys = allUsers ++ allWorkstations;

  # Phase D will add: "rclone-gdrive-token.age" = allUsers ++ [servers.nasbox];
}
