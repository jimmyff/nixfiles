let
  # machines to deploy to (keys from /etc/ssh/ssh_host_ed25519_key.pub or user keys for Darwin)
  systems = {
    nixelbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB2ECjQ848rCrkkBZ5bKI8lg34fEB9WOwktTDzwhTxnI root@nixos";
    jimmyff-mbp14 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAaZzF+34ChHrzl1Zr3crf60Snog3AQaHCrPNegyDitC jimmyff";
  };
  users = {
    # Original yubikey key - commented out but kept for Darwin debugging if needed
    # jimmyff = "age1yubikey1qg8nf40dfw4gprmywplggtg2wuvv55fcmujzrm65z8s3j6rhwje2vm3hhs7";
    
    # ed25519 SSH key derived age key
    jimmyff = "age1qzs9ac3a9j7rhf6t25hrk5jgaqhhu7mnsnuk4n8fz5hw2603v47s9fztm2";
  };
  allUsers = builtins.attrValues users;
  allSystems = builtins.attrValues systems;
in {
  "nextdns_nixelbook.age".publicKeys = allUsers ++ [systems.nixelbook];
  "android-release-key.jks.age".publicKeys = allUsers ++ [systems.nixelbook systems.jimmyff-mbp14];
}