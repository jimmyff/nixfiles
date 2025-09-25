```text
  __  _ __ __ __ ____   _____ ___ _    
 |_ \| |  V  |  V  \ `v' / __| __/ |   
  _\ | | \_/ | \_/ |`. .'| _|| _/ /    
 /___|_|_|_|_|_|_|_|_!_! |_|_|_|_/  _  
 |  \| | \ \_/ / __| | | | __/' _/ / | 
 | | ' | |> , <| _|| | |_| _|`._`./ /  
 |_|\__|_/_/ \_\_| |_|___|___|___/_/   

```

# jimmff/nixfiles/

✨ A Grimoire of Declarative Magicks...

```text

 nixfiles/
  ├── dotfiles/         # configs (managed by stow)
  ├── home_modules/     # Home Manager modules
  ├── hosts/            # Host config
  ├── nix_modules/      # Nix modules
  ├── projects/         # Development project templates
  ├── scripts/          # Utility scripts
  └── secrets/          # Encrypted secrets configuration

```

## Highlights

- **Multi-platform:** NixOS + macOS Darwin support
- **Project environments:** Declarative dev setup with direnv + Doppler secrets
- **Encrypted secrets:** agenix + private flake input for sensitive files
- **IDE integration:** Wrapped IDEs with Doppler secret injection
- **Git management:** [`gm.nu`](scripts/git-manager/) - mono repo git manager
- **Flutter/Dart management:** [`dartboard.nu`](scripts/dartboard/) - batch pub operations
- **Flutter hot reload:** [`flitter.rs`](scripts/flitter/) - hot reloading with debug info capture

---

## Usage

```shell
# System rebuilds
sudo nixos-rebuild dry-run|switch --flake /etc/nixos#nixelbook
sudo darwin-rebuild check|switch --flake ~/nixfiles/#jimmyff-mbp14
home-manager switch --flake ~/nixfiles

# Development projects (see projects/)
dev-setup && cd ~/Projects/<project> && direnv allow

# Updates & maintenance
nix flake update
sudo nixos-rebuild --rollback switch
```

Enable projects in host config: `development = { enable = true; projects = [ "project-name" ]; };`

---

## Resources

- [Search packages/options](https://search.nixos.org/)
- [Home Manager options](https://home-manager-options.extranix.com/)
- [NixOS Wiki](https://wiki.nixos.org/)

---

Jimmy Forrester-Fellowes 🌈 [jimmyff.co.uk](https://www.jimmyff.co.uk/)
