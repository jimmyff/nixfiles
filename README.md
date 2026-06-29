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
  ├── docs/             # Setup & ops runbooks
  ├── dotfiles/         # configs (managed by stow)
  ├── home/             # Home Manager modules
  ├── hosts/            # Host config
  ├── modules/          # Nix modules (core, workstation, development)
  ├── projects/         # Project repo map (repos.nix) + shared devshell-utils.nix
  ├── scripts/          # Utility scripts
  └── secrets/          # Encrypted secrets configuration

```

## Highlights

- **Multi-platform:** NixOS + macOS Darwin support
- **Granular updates:** Specialized nixpkgs inputs for independent update control per layer
- **Project environments:** Declarative dev setup with direnv
- **Encrypted secrets:** agenix (boot-time) + sops (on-demand) sharing one age identity, both backed by a private vault flake input
- **Workspace management:** [`✨glittering`](scripts/glittering/) - Multi-package orchestrator: git, test, analyze across Dart/Flutter workspaces
- **Package freshness:** [`flake-freshness.nu`](scripts/flake-freshness/) - monitor nix package versions across inputs

---

## Package Inputs

| Input | Branch | Purpose |
|-------|--------|---------|
| `pkgs-stable` | nixos-25.11 | Core system utilities |
| `pkgs-desktop` | nixos-unstable | Desktop environments |
| `pkgs-apps` | nixos-unstable | User applications |
| `pkgs-dev-tools` | nixos-unstable | Editors, LSPs, formatters |
| `pkgs-ai` | nixpkgs-unstable | AI tools (bleeding edge) |
| `pkgs-dev-flutter` | nixos-unstable | Flutter/Dart SDK |
| `pkgs-dev-rust` | nixos-unstable | Rust toolchain |
| `pkgs-dev-android` | nixos-unstable | Android SDK |

---

## Usage

```shell
# System rebuilds
sudo nixos-rebuild dry-run|switch --flake /etc/nixos#nixelbook
sudo darwin-rebuild check|switch --flake ~/nixfiles/#jimmyff-mbp14
home-manager switch --flake ~/nixfiles

# gcp-beacon (cloud push host) — run on nixbox:
./scripts/gcp-beacon/build-image.sh   # build GCE image (first-time / DR)
./scripts/gcp-beacon/deploy.sh        # push config to the running host

# Development projects (see projects/repos.nix)
# dev-setup bare-clones each repo to ~/projects/<project>/.bare and adds a
# default-branch worktree; enter the worktree to activate the devshell.
dev-setup && cd ~/projects/<project>/<branch> && direnv allow   # <branch> e.g. main

# Updates & maintenance
./scripts/flake-freshness/flake-freshness.nu  # Check for package updates
nix flake update                           # Update all inputs
nix flake lock --update-input pkgs-ai      # Update specific input
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
