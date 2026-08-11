# Structure — the judgment half

Load this to **create** a workstream, **restructure** a docs tree, or **close** a tracker. Reading one and ticking a box needs none of it.

## Where does this doc go

1. **Not a document at all — one small thing you noticed in passing?** → a plain bullet under the owning tracker's `## Snags`. Too small to schedule, blocked on nothing. See below.
2. **Future-tense scoping for one session?** → indented prose under its row in the owning tracker's `## Sessions`. Not a fifth kind — it dies on execution, the workstream death at row granularity. See Session briefs below.
3. **Will it be deleted when the work finishes?** → `workstreams/`. If you can't name the condition under which it dies, it isn't a tracker.
4. **Does it describe how something works, right now?** → `design/`. Present tense. Re-trued in place forever.
5. **Is it a choice made at a moment in time, including one you rejected?** → `decisions/`.
6. **Is it evidence, a guide, or a registry that won't change?** → `reference/`.
7. **None of these?** → it's probably a session record, and it belongs in the owning tracker's `## Log`. If it's genuinely none of the above, it likely shouldn't exist.

The four kinds are distinguished by **how they die**, not by subject. That's the whole taxonomy:

| Kind | Answers | Change rate | Death |
|---|---|---|---|
| `workstreams/` | what's left to do | often | **deleted** on completion |
| `design/` | how it works, why we chose it | rarely | never — re-trued in place |
| `decisions/` | a point-in-time choice | never | superseded, not edited |
| `reference/` | frozen evidence, guides, registries | never | rarely |

`decisions/` supersedes the conventional `adr/` — same concept, clearer name. A tree with an existing `adr/` has a rename to perform, not a rival vocabulary to reconcile.

## The five invariants

1. **One fact, one home.** Updating the same fact in two files means one is already wrong. Delete it; link instead of restating.
2. **Trackers are single-writer.** One workstream, one branch at a time. Not enforced by a stored lock — see below. It governs the file, never the work.
3. **Session records land in the owning tracker's `## Log`**, never a shared file. Durable doctrine promotes to `design/` in the same change.
4. **Trackers are mortal.** Delete on completion; the rationale already lives in `design/`. Nothing is archived.
5. **Blocked work is declared by the blocked side only** — a routed-gaps table, never a note in someone else's tracker.

## What is machine-read

`templates/` is the grammar — copy from it rather than reconstructing it. Only these are parsed, and everything else in a doc is prose:

- **YAML frontmatter** on all four kinds. One parser, not two. `workstream` declares `prefix` · `next_up` · `design`; `design` and `decision` declare `status` · `created` · `superseded_by`.
- **Rows under `## Sessions` and `## Log`**, in the form `- [ ] **PREFIX-n** — title`. Log rows settle as `— <date> — <link to design>` or `— <date> — no doctrine`, with an optional repeatable `— → THEIR-ID` crossover tail.
- **Plain `- ` bullets under `## Snags`**, counted and listed by `docs.nu snags`. No IDs and no checkboxes — a checkbox there is reported as a `syntax` note.
- **The `<!-- docs.nu:workstreams -->` markers** in `docs/README.md`, between which the table is generated.

**Rows must start at column 0.** Anything indented is prose or a comment and is never read — which is exactly what lets the templates carry worked examples inside the files the script parses, and a session brief live under its row.

**Links are resolved everywhere in a file**, not only in the parsed rows. A snag pointing at a file that doesn't exist yet must name it in backticks; written as a markdown link it becomes a `dead-link` finding.

The `no doctrine` form is load-bearing. Without it, every bug-fix and refactor session is permanently flagged as unpromoted doctrine, and the check trains people to write fake design links.

`docs.nu audit` reports a `syntax` note for checkbox rows that don't match, so a mis-shaped tracker fails loudly rather than silently reading as empty.

## Snags

A snag is something small you noticed while doing something else: worth doing, not worth a session of its own. It lives as a plain bullet under the owning tracker's `## Snags`, and it feeds the next session cut.

**A snag is not a routed gap.** A routed gap *can't* be done until something else lands, and it's declared by the blocked side. A snag *could* be done now. If a snag turns out to be blocked, routing it needs a session row — promote it to `## Sessions` first, or delete it and let it be re-noticed when it matters.

- **No IDs.** IDs are permanent and heavily cited; snags are ephemeral and deliberately uncitable. A snag worth citing is a session.
- **Cleared by deletion, never ticked.** A ticked snag is a permanent line in a file whose only defence is staying short. What was done is in `## Log`, or in git.
- **Survived two sessions? Promote it or delete it.** `docs.nu snags` reports a `since` column — sessions logged after the bullet appeared, derived from `git blame`, never stored. Every failure mode of that derivation reads as 0, so it nudges toward keeping, never toward a false promotion.
- **Noticed while working elsewhere?** It goes in *your* tracker, the same rule as the log. No tracker owns it at all? Say so in your reply and let the human place it — never open a shared TODO file.

**There is deliberately no audit check.** A tracker with 5 snags is healthy and so is one with 40, so any count threshold manufactures false positives. The asymmetry that settles it: routed gaps have an external clearing event a check can wait for, snags have only a habit. What bounds the list instead is **mortality** — the section is per-tracker and dies with it, so the worst case is one workstream's lifetime rather than a project's.

## Session briefs

A brief is one session's scoping — goal, scope cuts, open questions, exit, and any findings a scoping investigation produced that are recorded nowhere else. It rides as indented prose under its row in `## Sessions`, invisible to the parser by the column-0 rule. It is not a fifth kind: it dies on execution — the workstream death at row granularity — so the taxonomy is untouched.

- **Decisions about the work, never descriptions of the system.** Present tense is the smell: how something works belongs in `design/`. A planning sitting that settles design lands it there as `status: agreed` and the brief links to it — pinned design accreting in a tracker is how one triples past its cap.
- **Fidelity decays with distance.** Full briefs only for the session(s) the current state can actually inform — the next one or two, or one wave when a sitting lands the design that specifies them. Rows further out stay thin: goal, one line, a pointer. Work that can't be scoped until something else lands is a routed gap, not a session row. Cutting is event-driven — the tail of the session that just landed, or the sitting that opens a wave — never a scheduled pass over a backlog, which cuts briefs from a stale picture.
- **The tick is the death.** Deleting the brief is part of settling the log line: doctrine promotes to `design/`, negative results to `decisions/`, and corrections that bind later sessions are edited into those briefs — re-true the plan, never append a record. A log entry is a line, not a section.
- **The kickoff prompt is generated, not stored.** Compose it at session start from the tracker's header prose (the workstream-invariant constraints, stated once per tracker) plus the row's brief. The brief stores only what generation cannot recover.

`docs.nu audit` flags prose still indented under a **ticked** row — the one staleness check a brief affords, because the tick is a mechanical clearing event. Unticked briefs get no size or age check, for the snag reason: thresholds manufacture false positives, and a 4 KB brief carrying a real investigation is healthy. What keeps unticked briefs true is the re-truing discipline above — co-located with the log lines that would contradict them, and otherwise deliberately unstamped, like design-vs-code drift.

## Naming

A workstream declares `prefix:` in its frontmatter, defaulting to its filename uppercased. **Declaring rather than deriving is the point**: session IDs are the most-referenced strings in the system, and a tracker must be able to split or be renamed without invalidating every citation of `WIRING-3`. Sub-sessions are `WIRING-3a`. IDs are permanent — never renumber, never reuse.

There is no area vocabulary. Workstream names already carry that clarity, and where `design/` needs grouping the folder name *is* the area.

## Why there is no lock

An earlier design put `Lock: <worktree>` in the tracker header. It cannot work, and it fails **silently**.

A tracker is a tracked file, so a lock written on branch A is invisible from branch B until they merge — the moment it stops mattering. Both agents read `—`, both proceed, neither can tell. Acquiring the lock is itself a merge conflict on the mutex line.

So concurrency is **derived, not stored**. `docs.nu status` reports recent cross-branch activity per tracker from `git log --all --not HEAD`, which every worktree can see because they share one object store.

Blind spot, stated rather than hidden: **uncommitted work in another worktree is invisible** to any git-derived signal. If a hard mutex is ever wanted, the upgrade path is a file under `git rev-parse --git-common-dir` — shared by all worktrees, never committed, never merged. At this scale that's over-engineering.

## What single-writer does not mean

It governs **who writes the tracker file**, because markdown prose doesn't merge. It never scopes what code an agent may write, and it does not apply to `design/`, `reference/` or `decisions/`.

**Crossover protocol** — work that needs to touch another tracker:

- **Implementing across workstreams needs no protocol.** Build it, log it in your own tracker. UI built during a content session is part of that content session.
- **Ticking an item elsewhere:** no recent activity from another branch → just edit it. Activity shown → record it in your own log with a `— → THEIR-ID` tail, and the owner reconciles at merge.
- **Adding a snag to another tracker needs no protocol at all**, activity or not. ID-less independent bullets merge by keeping both sides, so a collision there is mechanical rather than prose.
- **Never block, never ask permission.** An agent that reads this as work ownership has failed worse than the drift it prevents.

## Size

Scoped by kind, because a flat cap fires on design docs that legitimately run long, and permanently unactionable findings are how an audit stops being read.

- **Trackers: ~25 KB hard.** They're the append-growth class and are read whole every session. Past it, harvest before splitting: executed briefs still standing, settled log lines past their use, log records grown into sections, design squatting in the tracker. Only if the live plan itself is over does it split by sub-stream — `wiring.md` → `wiring-transit.md`, each declaring its own `prefix:`.
- **`design/` and `reference/`: ~40 KB advisory**, reported as a note. They're re-trued in place, and splitting one manufactures boundary-straddling facts — invariant 1 in reverse.
- `design/` stays flat until a topic passes ~5 docs; then that topic gets a folder.

## Design status transitions

`agreed` → `active` → `implemented` → `superseded`. A superseded doc gains `superseded_by: <path>` and is otherwise left alone; its body is a record of what was true.

## Retiring a tracker — the harvest

Do this on **`main`**. A tracker deleted on a feature branch conflicts with concurrent edits, and a branch forked before the deletion silently resurrects it.

1. **Read the whole tracker**, `## Log` included.
2. **Ask: does this record anything we tried and rejected?** `design/` documents how things work, so a negative result has no home there and a harvest will classify it as non-durable and drop it. Route those to `decisions/` **first**.
3. **Promote durable doctrine to `design/`** — re-true the existing doc in place; only create a new one if the topic genuinely has no home.
4. **Re-home anything still open**: unfinished sessions move to the tracker that inherits them, keeping their original IDs. Routed gaps move to the tracker that's now blocked. Snags are re-read one by one — move the ones that still matter, delete the rest; `docs.nu snags` age is what makes that a decision rather than a coin flip.
5. **Check nothing links to it** — `docs.nu audit` will report dead links afterwards; better to fix them now.
6. **Delete it in a deletion-only commit** whose message names where it was harvested to: `docs: retire wiring tracker — harvested to design/content.md, decisions/0004`. That single-purpose commit is what makes `git log --grep` and `git revert` both work without prior knowledge.

Nothing is archived. An archived tracker is a tracker that didn't die — and the same holds for its log. An `archive/` bucket fails the kill test that defines every other kind (nothing kills it), and it becomes the escape hatch that skips harvests: once "archive it" exists it is always cheaper than promoting doctrine, and `design/` quietly stops being re-trued.

**Long streams die in waves.** A tracker that would live a year is a program wearing a tracker's clothes: cut trackers at wave scope, harvest each on completion, and let the successor declare the **same prefix** with `next_up` continuing the numbering — IDs stay permanent across waves. A drip-stream with no natural wave boundary bounds its log the way snags are bounded: a settled line whose doctrine is promoted and whose crossover tails are reconciled has discharged its duties — once it stops being near-term context, **delete it**; git is the history.

## Adopting this in an existing project

Restructuring is separate work, proposed and approved on its own — never a side effect of an unrelated task, and never inside a feature branch where other worktrees are concurrently editing docs.

1. Copy `templates/docs-readme.md` to `docs/README.md`.
2. Create `workstreams/`, `design/`, `decisions/`; rename any `adr/` to `decisions/`.
3. Split shared session files: each session record moves into the tracker that owns it. This is the expensive step and the reason the system exists.
4. `docs.nu status --write`, then `docs.nu audit` and work the findings.

## Rejected alternatives

Recorded so they aren't re-litigated. (The skill itself keeps no decision log — it is a tool, not a project.)

On the structure — shaped by a real 327 KB shared session file, edited from five worktrees:

- **One file per session.** Cleanest possible merges, but the tree accretes files nothing ever deletes — the shared file's mass with worse discoverability. Logs die with their tracker instead.
- **Git-derived status, no trackers at all.** "What's left" is a plan, and a plan is not recoverable from history — git answers what happened, never what's next.
- **A stored `Lock:` field.** Fails silently across branches — see Why there is no lock.
- **An area vocabulary** (`UI · AUTH · DATA · …`) on every session. Restates the filename; workstream names already carry it, and in `design/` the folder name is the area.
- **A hand-maintained workstream table in `docs/README.md`.** A duplicated fact in the one file every worktree writes, plus an audit check to police it. Generated by `status --write` instead, which removes both.

On session briefs:

- **A paragraph cap on the row.** A real brief carries findings a scoping investigation produced; a cap deletes them and the session re-buys them. The bound is mortality, not size — the snags precedent.
- **A `briefs/` or `sessions/` directory.** Briefs in other files don't get re-trued when a session lands, and the 90% path becomes a two-file read across a new merge surface.
- **A `## Next` section holding only the imminent briefs.** Bounded by construction, but it fights the batch cut: a design sitting briefs a whole wave at once so cheaper sessions can execute it.
- **Generated, not stored.** Zero staleness, but it discards considered scoping that generation cannot recover. Adopted as the kickoff mechanism over the stored brief instead.
- **A global backlog plus a scheduled planning pass.** A second home for the tracker's own rows, cutting briefs from a stale picture — cutting is event-driven, at the tail of the session that just landed. The graded homes already exist: snags (too small to schedule), thin rows (scheduled, unscoped), routed gaps (unscopable until an event).
