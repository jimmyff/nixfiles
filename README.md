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

Work in progress repo for nix files, configs, scripts etc.

```text

 nixfiles/
  ├── dotfiles/         # configs (managed by stow)
  ├── home_modules/     # Home Manager modules
  ├── hosts/            # Host config
  ├── nix_modules/      # Nix modules
  └── projects/         # Development project templates

```
---

## Resources

- [Nix options](https://search.nixos.org/options)
- [Nix packages](https://search.nixos.org/packages)
- [Home Manager options](https://home-manager-options.extranix.com/)
- [Wiki](https://wiki.nixos.org/)

---

## Usage

### System Management

```shell
# Rebuild nixelbook
sudo nixos-rebuild dry-run|switch --flake /etc/nixos#nixelbook

# Rebuild macbook via darwin
sudo darwin-rebuild check|switch --flake ~/nixfiles/#jimmyff-mbp14

# Update flake inputs (packages, dependencies)
nix flake update
```

### Development Environment

```shell
# Setup projects
dev-setup && cd ~/dev/<project> && direnv allow

# Enable projects in host config
development = { enable = true; projects = [ "project-name" ]; };
```

**Adding projects:** Create `projects/name/default.nix` with packages + repo, then rebuild.
