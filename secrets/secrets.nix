let
  # machines to deploy to (keys from /etc/ssh/ssh_host_ed25519_key.pub)
  systems = {
    nixelbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB2ECjQ848rCrkkBZ5bKI8lg34fEB9WOwktTDzwhTxnI root@nixos";
  };
  users = {
    jimmyff = "age1yubikey1qg8nf40dfw4gprmywplggtg2wuvv55fcmujzrm65z8s3j6rhwje2vm3hhs7";
  };
  allUsers = builtins.attrValues users;
  allSystems = builtins.attrValues systems;
in {
  "nextdns_nixelbook.age".publicKeys = allUsers ++ [systems.nixelbook];
}