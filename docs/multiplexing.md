# Multiplexing — kitty + herdr + mux

One kitty window, [herdr](https://herdr.dev) as the multiplexer, one always-on **hub** session you
curate. Launch with `mux` (alias `x`); `mux pin <project>` adds a project, `mux unpin <project>`
removes it.

herdr's hierarchy is **session → workspace → tab → pane**. mux maps the git-worktree project
layout onto it:

| herdr | is |
| ----- | -- |
| session | the **hub** (curated) — or a dedicated project via `mux --project` |
| workspace | a git worktree, labelled `<project>/<worktree>` (e.g. `osdn/main`) |
| tab / pane | views within a worktree |

One hub ⇒ one agent sidebar (⌘⌃⇧ `j`/`k`) across every project you're working on. Pin only what's
active; `unpin` when you're done — the git worktrees are untouched.

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

`mux` attaches the always-on hub; `pin`/`unpin` curate which projects it holds.

| Command | Action |
| ------- | ------ |
| `mux` / `x` | attach (or create) the hub |
| `mux <project>` | pin `<project>` if absent, focus its `main`, then attach the hub |
| `mux pin <project>` | add a hub workspace per worktree of `<project>` (idempotent) |
| `mux unpin <project>` | close the hub's `<project>/*` workspaces (**view-only** — git untouched) |
| `mux --project [name]` | dedicated per-project session, all worktrees (cwd if no name) |
| `mux reset` / `mux --reset` | delete the hub, then recreate it (run from **outside** herdr) |
| `mux --project [name] --reset` | same, for that project session |
| `mux worktree open <name>` | open (or focus) a worktree as a workspace (run **inside** herdr) |
| `mux worktree add <name>` | `glitter worktree add <name>`, then open it (**inside** herdr) |
| `mux worktree all` | open every worktree of the current project (**inside** herdr) |
| `mux sort` | reorder spaces alphabetically (current session inside herdr; the hub outside) |

- **Hub-scoped:** `pin`/`unpin`/`mux <project>` target the hub's socket directly, so they behave
  identically from inside the hub, another session, or outside herdr. The hub must be running —
  `mux` creates it (a session can't be populated before its first attach).
- **Labels & order:** every worktree workspace is `<project>/<worktree>`, in the hub *and* in a
  `--project` session, kept **alphabetically sorted** (the `~` scratch shell stays first). mux
  auto-sorts after `pin` and `worktree` ops; `mux sort` re-sorts on demand. herdr 0.7.1 can't
  reorder via its CLI, so this drives its socket API (`workspace.move`) through `nc` — a silent
  no-op if `nc` is unavailable. Switch with ⌘⌃ `j`/`k` or the picker (`ctrl+b` `w`).
- **Worktrees:** enumerated from `glittering worktree list --cached` (raw `git worktree list`
  fallback). **Adding:** `mux worktree add <name>` delegates to `glitter worktree add` (submodules/
  cache/`pub get`), then opens it. herdr's native `worktree open` **can't** use the bare-repo layout
  (`linked_worktree_source` — no non-linked parent), so mux opens plain workspaces (`workspace
  create --cwd`).
- **direnv:** `mux worktree add` pre-runs `direnv allow` on the new worktree's `.envrc` (you just
  created it, so it's trusted). Opening an *existing* worktree does **not** auto-allow — run
  `direnv allow` yourself after reviewing.
- **`--project` sessions** land herdr's default pane at `main` (or the cwd's worktree); run
  `glitter overview` for worktree status, or `mux worktree all` to open them all.
- **Session name (`--project`):** `$MUX_SESSION` → the project name → cwd basename outside `~/projects`.

## The hub

The always-on **`hub`** session is where you work. Fresh, it holds a single `~` scratch shell; `mux pin <project>` adds a
workspace per git worktree (labelled `<project>/<worktree>`), `mux unpin <project>` closes them
again — **view-only, the git worktrees are never touched**. Everyday shortcut: `mux <project>`
pins (if needed) and focuses the project's `main`.

Because pin/unpin are hub-scoped, you can curate from anywhere — a project session, or a plain
shell outside herdr — then **⌘⌥ space** (goto) over to the hub. Within the hub, switch projects and
worktrees with **`ctrl+b` `w`** (workspace picker) or ⌘⌃ `j`/`k`.

If the hub isn't running yet, `pin` errors — run `mux` once to create it. `mux --reset` (from
**outside** herdr) tears the hub down and recreates it fresh (a single `~` shell).

Need a single project in isolation? `mux --project [name]` opens a dedicated session (all its
worktrees, same `<project>/<worktree>` labels), resettable with `mux --project [name] --reset`.

## Applying changes

- **herdr config** (`dotfiles/herdr/config.toml`) — `herdr server reload-config` (or
  `herdr server stop` + relaunch). Live-symlinked; no rebuild.
- **mux** (`mux.nu`) — `darwin-rebuild switch` (baked into a `writeScriptBin`).
- **aerospace / niri** — live-reload on save / `aerospace reload-config`.
- **kanata home-row mods** — edit `dotfiles/kanata/kanata-layers.kbd`, then `darwin-rebuild switch`
  (macOS) / `nixos-rebuild switch` (Linux); the daemon restarts automatically.
- **Headless** — herdr is desktop-only (gated on S7 verification); headless boxes have no
  multiplexer (SSH tunnels only).
