---
name: project-docs
description: Structure for project planning and design docs — workstream trackers, design records, decisions. Use when creating a tracker or a design doc, restructuring a docs tree, closing out a workstream, deciding where a new doc goes, or auditing docs for drift. Triggers include "where should this doc go", "start a workstream", "close out this tracker", "are these docs stale", "restructure the docs". SKIP for package READMEs, changelogs, code comments and one-off notes — and skip for recording what a session delivered, which needs nothing but the tracker's own `## Log`.
---

# project-docs

Planning and design docs, structured so every fact has one home and finished work gets deleted.

## The shape

```
docs/
├── README.md      entry point; its workstream table is generated
├── workstreams/   what's left to do — deleted on completion
├── design/        how it works and why — re-trued in place
├── decisions/     point-in-time choices — superseded, never edited
└── reference/     frozen evidence, guides, registries
```

Each kind is defined by **how it dies**. If you can't say what kills a doc, it's in the wrong folder.

## Invariants

1. **One fact, one home.** Two files stating the same fact means one is already wrong — link, don't restate.
2. **Tracker files are single-writer** — one tracker, one branch at a time. The file, not the work. Derived from git, never locked.
3. **Session records go in the owning tracker's `## Log`** — never a shared session file.
4. **Trackers are mortal** — deleted on completion, never archived. The rationale already lives in `design/`.
5. **Blocked work is declared by the blocked side only** — a routed-gaps table, not a note in someone else's tracker.

## What this does not restrict

Single-writer governs **who writes the tracker file**, because markdown prose doesn't merge. It never scopes what code you may write. Cross-cutting implementation is normal and expected, and none of this applies to `design/`, `reference/` or `decisions/`.

- Implementing across workstreams needs no protocol. Build it, log it in **your own** tracker.
- Ticking an item in another tracker: no recent activity from another branch → **just edit it**. Activity shown → record it in your own log with a `— → THEIR-ID` tail, and the owner reconciles at merge.
- **Never block and never ask permission for this.**

## Never restructure unasked

If a project has no `docs/workstreams/`, it has not adopted this structure. Follow local convention for the current task. Propose migration as separate work, done on the main branch — never as a side effect.

## The 90% path

Reading a tracker and ticking a box needs nothing else on this page. Its `## Sessions`, `## Snags` and `## Log` headers carry their own syntax — follow the shape already in the file.

## Commands

`nu ~/nixfiles/dotfiles/ai/skills/project-docs/scripts/docs.nu <cmd>`

| Command | Does |
|---|---|
| `status --path docs` | per tracker: prefix · next up · size · open/total · other-branch activity |
| `status --path docs --write` | regenerate the README workstream table *(writes)* |
| `new <name> --path docs` | scaffold a tracker from the template *(writes)* |
| `audit --path docs` | size · dead links · orphans · closure · ID collisions · open logs · crossovers · leftover briefs |
| `selftest` | check the script against its fixture |

`audit` never acts: findings are to fix, notes are to know.

## Go deeper

Load `structure.md` to **create** a workstream, **restructure** a tree or **close** one — it carries the where-does-this-go decision tree, session-brief rules, the harvest procedure, size rules, adoption steps and the rejected alternatives.

## What the audit cannot see

Semantic duplication · a doc gone stale against the code it describes (the most common real rot, and deliberately unstamped) · uncommitted work in other worktrees. **A clean audit is not a healthy tree.**
