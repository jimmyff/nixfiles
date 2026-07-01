# Multiplexing — kitty + herdr + mux

One kitty window, [herdr](https://herdr.dev) as the multiplexer, one named session per project.
Launch with `mux` (alias `x`).

herdr's hierarchy is **session → workspace → tab → pane**. mux maps the git-worktree project
layout onto it:

| herdr | is |
| ----- | -- |
| session | a project — the `~/projects/<name>` dir holding `.bare` |
| workspace | a git worktree (herdr owns the worktree↔workspace binding via `[worktrees] directory`) |
| tab / pane | views within a worktree |

The always-running **`default`** session doubles as the cross-project hub (`mux dash`).

## Keyboard layering

herdr grabs **only its bound chords** — everything else (all `Ctrl`, etc.) flows to the focused
TUI (Claude, Helix). No "locked mode" to toggle.

| Keys | Go to |
| ---- | ----- |
| ⌃ (anything) | the focused TUI — herdr ignores it (except its `ctrl+b` prefix) |
| ⌘⌥ + … | **herdr panes** — focus, split, zoom, rename, detach, resize |
| ⌘⌃ + … | **herdr tabs + workspaces** — switch / new / close / rename |
| ⌘⌥ space | **herdr** — session navigator (goto) |
| ⌘ / ⌘⇧ + `hjkl` | aerospace / niri — window focus / move |
| ⌥ / ⌥⇧ + `j` `k` | aerospace / niri — switch / move workspace |

kanata makes the modifiers from home-row holds: `a`/`;`=⌘, `s`/`l`=⌥, `d`/`k`=⌃, `f`/`j`=⇧
(see `docs/darwin-install.md`). `ctrl+b` is herdr's prefix fallback for every chord below.

## herdr keys

| Keys | Action |
| ---- | ------ |
| ⌘⌥ `hjkl` | focus pane (left/down/up/right) |
| ⌘⌥ `n` / `m` | split right / down |
| ⌘⌥⇧ `hjkl` | resize pane |
| ⌘⌥ `f` / `r` / `d` | zoom / rename / detach pane |
| ⌘⌃ `h` / `l` | previous / next tab |
| ⌘⌃ `n` / `w` / `r` | new / close / rename tab |
| ⌘⌃ `j` / `k` | previous / next workspace (worktree) |
| ⌘⌃⇧ `n` / `w` / `r` | new / close / rename workspace |
| `ctrl+b` `w` | workspace picker |
| ⌘⌃⇧ `j` / `k` | focus next / prev agent in the sidebar |
| ⌘⌥ space | session navigator (jump between sessions) |

Bindings live in `dotfiles/herdr/config.toml`; each is `[ctrl+b fallback, ⌘-chord]`. Apply edits
with **`herdr server reload-config`** — the persistent server does not auto-reload.

## mux

`mux` resolves a herdr session + landing dir from the cwd, then attaches or creates it.

| Command | Action |
| ------- | ------ |
| `mux` / `x` | launch or attach the project session for the cwd |
| `mux reset` | delete the session, then relaunch (run from **outside** herdr) |
| `mux dash` | populate the `default` session with a terminal per project root, then attach |
| `mux worktree open <name>` | open (or focus) a worktree as a workspace (run **inside** herdr) |
| `mux worktree add <name>` | `glitter worktree add <name>`, then open it (**inside** herdr) |
| `mux worktree all` | open every worktree of the current project (**inside** herdr) |

- **Session name:** `$MUX_SESSION` → the project (the `~/projects/<name>` dir holding `.bare`) →
  cwd basename for anything outside `~/projects`.
- **Worktree:** enumerated from `glittering worktree list --cached` (raw `git worktree list`
  fallback); `mux` lands in the cwd's worktree, or `main` at a project root. Switch open worktrees
  with ⌘⌃ `j`/`k` or the workspace picker.
- **Adding worktrees:** `glitter worktree add <name>` (sets up submodules/cache/`pub get`), then
  `mux worktree open <name>`. herdr's native `worktree open`/`new_worktree` **don't** work with the
  bare-repo layout (`linked_worktree_source` — no non-linked parent), so `mux worktree` opens them
  as plain workspaces (`workspace create --cwd`).
- herdr can't populate a session before its (blocking) attach, so `mux` lands herdr's default
  pane — run `glitter overview` for worktree status.

## mux dash

The always-running **`default`** session is the cross-project hub. `mux dash` ensures it has one
workspace — a terminal at the project root — for every `~/projects/*/.bare` project plus
`DASH_EXTRA` (`~/nixfiles`), deduped by label, then attaches. Re-run any time; only missing
projects are added. Navigate with **⌘⌥ space** (goto, across sessions) and **`ctrl+b` `w`**
(workspace picker, within). Add always-on folders via the `DASH_EXTRA` const in `mux.nu`.

## Applying changes

- **herdr config** (`dotfiles/herdr/config.toml`) — `herdr server reload-config` (or
  `herdr server stop` + relaunch). Live-symlinked; no rebuild.
- **mux** (`mux.nu`) — `darwin-rebuild switch` (baked into a `writeScriptBin`).
- **aerospace / niri** — live-reload on save / `aerospace reload-config`.
- **kanata home-row mods** — edit `dotfiles/kanata/kanata-layers.kbd`, then `darwin-rebuild switch`
  (macOS) / `nixos-rebuild switch` (Linux); the daemon restarts automatically.
- **Headless** — herdr is desktop-only (gated on S7 verification); headless boxes have no
  multiplexer (SSH tunnels only).
