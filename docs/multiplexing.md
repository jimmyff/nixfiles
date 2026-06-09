# Multiplexing — kitty + zellij + mux

One kitty window, zellij as the only multiplexer, one named session per project
(**session = workspace**). Launch with `mux` (alias `x`); switch via zellij's
native session-manager.

## Keyboard layering (bottom → top)

| Layer | Owner | Role |
| ----- | ----- | ---- |
| 0 | kanata (`dotfiles/kanata/kanata.kbd`) | Home-row mods *produce* the modifiers |
| 1 | aerospace | ⌘ / ⌥ → windows & spaces |
| 1 | macOS App Shortcuts | ⌃ → **Chromium menus only** (`modules/core/darwin/system-defaults.nix`) |
| 1 | zellij | **Locked by default** — all ⌃ reach the focused TUI; ⌘⌥ → zellij nav |
| 1 | kitty | Passes ⌃ through (tab keys are `no_op`) |

### Home-row mods (kanata, layer 0)

Hold a home-row key for its modifier; tap for the letter. Physical modifier keys
still work (`process-unmapped-keys yes`).

| Modifier | Left | Right |
| -------- | ---- | ----- |
| ⌃ Ctrl  | `d` | `k` |
| ⌘ Cmd   | `a` | `;` |
| ⌥ Alt   | `s` | `l` |
| ⇧ Shift | `f` | `j` |

Chord ergonomics: `Ctrl+s` (→ TUI) = hold `d` + tap `s`; `Ctrl+g` (toggle) =
hold `d` + tap `g`.

## zellij: locked by default

Sessions start **locked** so every `Ctrl` passes straight to the focused TUI
(Claude Code, Helix), which are `Ctrl`-heavy. To drive zellij itself:

- **`Ctrl+g`** — toggle locked ↔ normal (then `Ctrl+t` tabs, `Ctrl+p` panes, …).
- **⌘⌥ hjkl / arrows** — focus + tab-edge switch (works **locked**; dodges aerospace).
- **⌘⌥ +/− / =** — resize. **⌘⌥ [ / ]** — swap layout. (Both work locked.)
- **⌘⌃h / ⌘⌃l** — previous / next tab (restored from kitty; works locked).
- **`Ctrl+g`, then `Ctrl+o` `w`** — open the session-manager to switch sessions.

Trade-off: Claude's external-editor on `Ctrl+g` is shadowed by the toggle, so it's
rebound to **`Ctrl+E`** (`dotfiles/claude/keybindings.json`); the `Ctrl+X Ctrl+E`
chord still works.

## mux — workspace launcher

`mux` (alias `x`) resolves a session name + private layout from the cwd, then
attaches to or creates the matching zellij session.

| Command | Action |
| ------- | ------ |
| `mux` / `x` | Launch/attach the workspace for the cwd |
| `mux reset` | Delete the session, then relaunch (escape a bad resurrection) |
| `mux init`  | Scaffold a `.zellij.kdl` here (won't clobber an existing one) |

Session name (first match wins): `$env.ZJ_SESSION` → `~/Projects/<name>/workspace`
→ git repo basename → cwd basename. Layout: `$env.ZJ_LAYOUT` → nearest `.zellij.kdl`
walking up to the root → none (falls back to `default_layout "compact"`).

### Layout convention — `.zellij.kdl`

Per-project layout at the repo root. Project layouts hold launch commands, so they
live in the **private** project repo (nixfiles is public). `~/nixfiles/.zellij.kdl`
is the committed scaffold (`edit` + `git` tabs, compact bar) and is exactly what
`mux init` writes.

## Persistence & applying changes

- **Persistence is on** (`session_serialization` default + `serialize_pane_viewport
  true`). Sessions survive restarts; resurrecting **re-runs pane commands** — keep
  heavy commands (e.g. `flutter run`) out of auto-resurrected layouts, or `mux reset`.
- **zellij config is a live symlink** (`dotfiles/zellij/config.kdl`): edits apply on
  the next zellij **restart**, not `darwin-rebuild`; `darwin-rebuild rollback` won't
  revert it — back out via git. zellij's config UI writes *through* the symlink, so
  keep manual edits minimal.
- **kitty / mux / Chromium defaults** apply on `darwin-rebuild switch` (Chromium also
  needs `killall cfprefsd` + relaunch).
