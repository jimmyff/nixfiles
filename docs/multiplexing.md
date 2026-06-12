# Multiplexing — kitty + zellij + mux

One kitty window, zellij as the only multiplexer, one named session per project
(**session = workspace**). Launch with `mux` (alias `x`).

## Keyboard layering

| Keys | Go to |
| ---- | ----- |
| ⌃ (anything) | the focused TUI — zellij is **locked by default** (Claude, Helix) |
| ⌘⌥ + home row / symbols / arrows | **zellij** — nav, resize, detach (works while locked) |
| ⌘ / ⌘⇧ + `hjkl` | aerospace — window focus / move |
| ⌥ / ⌘⌥ + top·bottom-row letter | aerospace — switch / move to workspace |
| ⌃ in Chromium | menu shortcuts — tabs, address bar |

kanata makes the modifiers from home-row holds: `a`/`;`=⌘, `s`/`l`=⌥, `d`/`k`=⌃, `f`/`j`=⇧.
So `Ctrl+s` = hold `d` + tap `s`. The **internal keyboard** gets these from the kanata daemon
(see `docs/darwin-install.md`); the **Moonlander** has the same mods baked into its QMK firmware.

## zellij keys

Sessions start **locked**, so every `Ctrl` reaches the TUI. To drive zellij:

| Key | Action |
| --- | ------ |
| `Ctrl+g` | toggle locked ↔ normal (then `Ctrl+t` tabs, `Ctrl+p` panes, …) |
| ⌘⌥ `hjkl` / arrows | move focus, or switch tab at the edge |
| ⌘⌥ `+ − =` / `[ ]` | resize / swap layout |
| ⌘⌃ `h` `l` | previous / next tab |
| ⌘⌥ `d` | detach |
| `Ctrl+g` → `Ctrl+o` `w` | session-manager (switch sessions) |

`Ctrl+g` shadows Claude's external-editor, so that's rebound to `Ctrl+E`
(`dotfiles/claude/keybindings.json`).

## mux

`mux` resolves a session name + layout from the cwd, then attaches or creates it.

| Command | Action |
| ------- | ------ |
| `mux` / `x` | launch or attach the workspace for the cwd |
| `mux reset` | delete the session, then relaunch (escape a bad resurrection) |
| `mux init` | scaffold a `.zellij.kdl` here |

- **Session name:** `$ZJ_SESSION` → `~/Projects/<name>/workspace` → git repo → cwd basename.
- **Layout:** `$ZJ_LAYOUT` → nearest `.zellij.kdl` → the `default_layout` fallback. That
  fallback is `jimmyff` (`dotfiles/zellij/layouts/jimmyff.kdl`, classic tab + status bar),
  used *only* when no `.zellij.kdl` is found — project layouts bypass it.

`jimmyff.kdl` is the single source of truth for the default layout: it's both the bare-session
fallback and what `mux init` copies to seed a project's `.zellij.kdl`. (Zellij has no cross-file
template inheritance, so a copy is a snapshot — re-run `mux init` to re-seed after editing it.)

A project's `.zellij.kdl` lives at its repo root, in the **private** repo (layouts hold launch
commands; nixfiles is public). `~/nixfiles/.zellij.kdl` is the committed scaffold `mux init` writes.

## Applying changes

- **Live symlinks** — `dotfiles/zellij`, `dotfiles/aerospace`, `.zellij.kdl`: apply on the next
  zellij start / `aerospace reload-config`, not `darwin-rebuild`. Revert via git.
- **kitty / mux / Chromium** — `darwin-rebuild switch` (Chromium also needs `killall cfprefsd`).
- **kanata home-row mods** — edit `dotfiles/kanata/kanata-layers.kbd`, then `darwin-rebuild switch`
  (macOS) / `nixos-rebuild switch` (Linux); the daemon restarts automatically.
- Persistence is on; resurrecting **re-runs pane commands** — `mux reset` to start clean.
