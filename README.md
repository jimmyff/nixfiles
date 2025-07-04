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
  └── nix_modules/      # Nix modules

```

---

## Usage

```shell

# Rebuild macbook via darwin
sudo darwin-rebuild check --flake ~/nixfiles/#jimmyff-mbp14


```
