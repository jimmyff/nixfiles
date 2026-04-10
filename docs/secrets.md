# Secrets

All secrets live encrypted in a private `nixfiles-vault` flake input. System-level secrets are decrypted at activation via **agenix** to fixed paths on disk; everything else stays encrypted at rest and is decrypted **on demand** via **sops** into an ephemeral tempfile that's wiped when the consuming command exits. Both tools share one identity — your SSH key (`~/.ssh/id_ed25519`).

| Need | Tool | Decrypts |
| --- | --- | --- |
| System service at boot/activation | agenix | At activation, to fixed paths |
| Human-triggered command (build/sign) | sops | On demand, ephemeral tempfile |

## Bootstrap a new machine

Requirements: `~/.ssh/id_ed25519` exists and is **not** passphrase-protected (`ssh-to-age` can't decrypt encrypted keys non-interactively).

Rebuild the system. The activation script in `modules/development/sops-wrappers.nix` derives `~/.config/sops/age/keys.txt` from the SSH key. If it failed, run manually:

```bash
mkdir -p ~/.config/sops/age
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

## agenix workflow

For secrets consumed by system services at activation time.

1. Declare in `secrets/secrets.nix`:
   ```nix
   "my-secret.age".publicKeys = allUsers ++ allSystems;
   ```
2. Sync rules and create the encrypted file:
   ```bash
   cp secrets/secrets.nix secrets/vault/
   cd secrets/vault && agenix -e my-secret.age
   git add my-secret.age secrets.nix && git commit -m "Add my-secret" && git push
   cd ~/nixfiles && nix flake update nixfiles-vault
   ```

Use in a module:
```nix
age.secrets.my-secret = {
  file = nixfiles-vault + "/my-secret.age";
  mode = "600";
  owner = username;
};
```

Access via `config.age.secrets.my-secret.path` (decrypted at activation).

## sops workflow

For on-demand secrets: build-time passwords, release keystores, signing keys. Encrypted files live under `nixfiles-vault/sops/`.

### Adding an env-var secret

```bash
cd secrets/vault/sops
sops $PROJECT-<name>.yaml    # editor opens; write KEY: "value" lines
git add $PROJECT-<name>.yaml && git commit -m "Add $PROJECT-<name>" && git push
cd ~/nixfiles && nix flake update nixfiles-vault
```

### Adding a binary file secret

`creation_rules` match on the input filename, so piping fails with "no matching creation rules found". Copy to the target name first, then encrypt in place:

```bash
cd secrets/vault/sops
cp /path/to/key.jks $PROJECT-<name>.jks.sops
sops --encrypt --in-place --input-type binary --output-type binary $PROJECT-<name>.jks.sops
```

**Verify before committing** — if the in-place encrypt silently didn't run, you'll be committing plaintext:

```bash
file $PROJECT-<name>.jks.sops         # expect: JSON data (NOT "Java KeyStore")
head -c 50 $PROJECT-<name>.jks.sops   # expect: { "data": "ENC[AES256_GCM,...
```

Then commit and update the flake input.

### Editing an existing secret

Always edit in place — never decrypt → edit → re-encrypt manually.

```bash
cd secrets/vault/sops
sops $PROJECT-<name>.yaml    # or $PROJECT-<name>.jks.sops for binary
```

### Using a sops secret at runtime

For one-off commands, invoke sops directly:

```bash
sops exec-env $NIXFILES_VAULT/sops/$PROJECT-<name>.yaml -- some-command
sops exec-file --no-fifo $NIXFILES_VAULT/sops/$PROJECT-<name>.jks.sops 'some-command --key {}'
```

For recurring workflows, define a wrapper script — see the next section.

### Writing a wrapper script

The pattern: template the vault's nix store path into a `writeShellScriptBin` at build time, decrypt to a `mktemp -d` tempdir, export env vars, run the user command as a child, wipe the tempdir on EXIT.

Minimal sketch (add to a nix module that receives `nixfiles-vault` via specialArgs):

```nix
my-signing-wrapper = pkgs.writeShellScriptBin "my-signing-wrapper" ''
  set -euo pipefail
  SOPS=${pkgs.sops}/bin/sops
  KEYSTORE="${nixfiles-vault}/sops/$PROJECT-key.jks.sops"
  ENVFILE="${nixfiles-vault}/sops/$PROJECT-passwords.yaml"

  [ "''${1:-}" = "--" ] || { echo "usage: my-signing-wrapper -- <cmd>" >&2; exit 64; }
  shift

  TMPDIR_KS=$(mktemp -d -t my-signing-XXXXXXXX)
  trap 'rm -rf -- "$TMPDIR_KS"' EXIT

  "$SOPS" --decrypt --input-type binary --output-type binary \
    --output "$TMPDIR_KS/key.jks" "$KEYSTORE"
  chmod 600 "$TMPDIR_KS/key.jks"
  export KEYSTORE_PATH="$TMPDIR_KS/key.jks"

  "$SOPS" exec-env "$ENVFILE" -- "$@"
'';
```

Register it in `environment.systemPackages`. Key properties:

- **Nix-store path templating** — `${nixfiles-vault}` is substituted at build time, so the wrapper knows exactly where to find encrypted files with no runtime env-var dependency.
- **Child, not exec** — running the command as a child (rather than `exec`ing it) ensures the bash EXIT trap fires afterwards to clean up the tempdir.
- **EXIT trap** — bash fires this on any exit path (success, error, SIGINT, SIGTERM), so the tempdir is wiped even if the command is interrupted.

For a worked example with multiple modes and two keystores, see `modules/development/sops-wrappers.nix`.

## Apple certificate renewal

Three signing certs in sops via `rocketware-apple-sign`. Apple Distribution and Mac Installer Distribution expire annually.

```bash
cd /tmp && mkdir apple-renew && cd apple-renew
openssl genrsa -out cert.key 2048
openssl req -new -key cert.key -out cert.csr \
  -subj "/emailAddress=<APPLE_ID>/CN=Rocketware Ltd/C=GB"
# Upload cert.csr to developer.apple.com → Certificates → + → select type → download .cer
openssl x509 -inform DER -in downloaded.cer -out cert.pem
openssl pkcs12 -export -inkey cert.key -in cert.pem -out cert.p12 -name "<identity name>"
open cert.p12  # import into login keychain for Xcode
cp cert.p12 ~/nixfiles/secrets/vault/sops/<sops-filename>
cd ~/nixfiles/secrets/vault/sops
sops --encrypt --in-place --input-type binary --output-type binary <sops-filename>
file <sops-filename>  # verify: "JSON data"
cd ~/nixfiles/secrets/vault && git add -A && git commit -m "Renew <cert>" && git push
cd ~/nixfiles && nix flake update nixfiles-vault && darwin-rebuild switch
rm -rf /tmp/apple-renew
```

Sops files: `rocketware-apple-sign-app-distribution.p12.sops`, `rocketware-apple-sign-mac-installer.p12.sops`, `rocketware-apple-sign-developer-id-app.p12.sops`. Passwords in `rocketware-apple-sign.yaml` — reuse on renewal.

## Managing sops recipients

To add a new machine or rotate a key, update the recipient list in `.sops.yaml` and re-encrypt every file.

1. On the new machine: `ssh-to-age < ~/.ssh/id_ed25519.pub`
2. Add the pubkey to `creation_rules.key_groups[].age` in `secrets/vault/sops/.sops.yaml`
3. Re-encrypt all files with the expanded recipient set:
   ```bash
   cd secrets/vault
   sops updatekeys sops/*.yaml sops/*.sops
   git add sops && git commit -m "Add <hostname> as sops recipient" && git push
   cd ~/nixfiles && nix flake update nixfiles-vault
   ```
4. Rebuild on the new machine — activation bootstraps its age identity.

## Appendix: first-time vault setup

Only needed when creating `secrets/vault/sops/` for the first time. Create `.sops.yaml` with your age recipient:

```yaml
creation_rules:
  - path_regex: \.(yaml|sops)$
    key_groups:
      - age:
          - age1...your-recipient-here...
```

Get your recipient with `ssh-to-age < ~/.ssh/id_ed25519.pub`. The regex matches the input filename as typed (not relative to `.sops.yaml`'s location), so `\.(yaml|sops)$` is the simplest rule that catches both env-var and binary files in the same directory.
