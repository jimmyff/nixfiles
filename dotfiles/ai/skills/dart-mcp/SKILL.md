---
name: dart-mcp
description: Official Dart/Flutter MCP server (tools appear as mcp__dart__*). Use for the live-app runtime loop (launch, hot reload, runtime errors, screenshots, widget tree + driver interaction), pub.dev search, and grepping/reading dependency source. NOT for workspace-wide test/analyze/git — glittering stays the default there. If a project lacks .mcp.json, symlink the canonical one (~/nixfiles/dotfiles/ai/mcp.json) — never write a copy.
---

# dart-mcp — official Dart/Flutter MCP server

`dart mcp-server` is built into Dart >= 3.9 and exposes analysis, pub, and live-app tooling over MCP. The server is experimental and evolving — if a tool misbehaves, fall back to raw `dart`/`flutter` commands and mention the failure.

## Division of labour: glittering vs dart MCP

Glittering remains the default for anything workspace-wide (test, analyze, git status/commit/push/pull) — see the /glittering skill. The dart MCP server's unique value is the live-app runtime loop and package research.

| Task | Use |
|---|---|
| Workspace-wide tests / analysis / git | `glittering` |
| Launch app, hot reload, logs, runtime errors, screenshots | dart MCP runtime tools |
| Interact with the running UI (tap, type, scroll) | `flutter_driver_command` |
| Inspect / select widgets in the running app | `widget_inspector` |
| Search pub.dev for packages | `pub_dev_search` |
| Grep or read source of resolved dependencies | `rip_grep_packages`, `read_package_uris` |
| Targeted fixes/format/tests on specific files | `analyze_files`, `dart_fix`, `dart_format`, `run_tests` |

## Setup: per-project .mcp.json

On Jimmy's machines `.mcp.json` is a nix-managed symlink to `~/nixfiles/dotfiles/ai/mcp.json` (the single canonical config; servers: `dart`, `chrome-devtools`). Home-manager activation places it in every checkout under `~/projects/`, and the glittering global worktree hook seeds new worktrees. If a checkout is missing it, symlink it — never write a copy:

    ln -s ~/nixfiles/dotfiles/ai/mcp.json .mcp.json

Server-list changes go in the canonical file, not per-project. Both servers are pre-approved in user settings (`enabledMcpjsonServers`) and their tools allowed (`mcp__dart`, `mcp__chrome-devtools`), so they connect without prompts. A new `.mcp.json` needs a session restart (or `/mcp` reconnect) to pick up.

## The live-app dev loop

Runtime tools need an active DTD (Dart Tooling Daemon) connection. Two ways to get one:

1. Agent-launched: `list_devices` → `launch_app` (wires up DTD automatically).
2. User-launched: user runs `flutter run --print-dtd` and shares the URI; pass it to the `dtd` tool.

Then iterate:

1. Edit code.
2. `hot_reload` — use `hot_restart` when state, initializers, or main() changed.
3. `get_runtime_errors` after every reload; `get_app_logs` when debugging behaviour.
4. Verify visually: `flutter_driver_command` with `screenshot` returns a PNG — look at it rather than assuming the change worked.
5. `stop_app` when done.

Driver interaction works most reliably on apps launched via `launch_app`; an attached user-run app may not have the driver extension enabled.

## Widget targeting rules

- ALWAYS fetch the widget tree before driver interaction: `widget_inspector` command `get_widget_tree` (start with `summaryOnly: true`). Never guess widget selectors or finders.
- When the user says "this widget": `set_widget_selection_mode` on, ask them to click it in the app, then `get_selected_widget`.
- Driver commands: `tap`, `enter_text`, `scroll`, `waitFor`, `get_text`, `get_offset`, `get_diagnostics_tree`, `screenshot`.

## Package research

- Dependencies are added only with Jimmy's explicit consent — propose, don't add.
- Prefer internal packages (e.g. rocket_kit) — check whether the capability already exists there before considering third-party options.
- `pub_dev_search` — find candidate packages to propose.
- `rip_grep_packages` / `read_package_uris` — grep and read the actual source of resolved dependencies instead of guessing APIs.
- `pub` — get/upgrade for one package (workspace-wide: `glittering get`/`upgrade`); add/remove only after consent.

## Caveats

- Experimental: tool names and behaviour may shift between Dart SDK releases.
- Runtime tools error without a DTD connection — connect first (`launch_app` or `dtd`).
- Each session in a project with `.mcp.json` spawns a Dart VM for the server — expected; every checkout under `~/projects/` has one.
