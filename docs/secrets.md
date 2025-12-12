# Secrets

Encrypted with agenix, stored in private `nixfiles-vault` repo (flake input).

## Adding a Secret

1. Declare in `secrets/secrets.nix`:
   ```nix
   "my-secret.age".publicKeys = allUsers ++ allSystems;
   ```

2. Sync rules to vault:
   ```bash
   cp secrets/secrets.nix secrets/vault/
   ```

3. Create encrypted file:
   ```bash
   cd secrets/vault
   agenix -e my-secret.age
   # Editor opens → enter secret → save → exit
   ```

4. Push vault and update flake:
   ```bash
   cd secrets/vault
   git add my-secret.age secrets.nix && git commit -m "Add my-secret" && git push
   cd ~/nixfiles
   nix flake update nixfiles-vault
   ```

## Using a Secret

In a module:
```nix
age.secrets.my-secret = {
  file = nixfiles-vault + "/my-secret.age";
  mode = "600";
  owner = username;
};
```

Access via `config.age.secrets.my-secret.path` (decrypted at runtime).
