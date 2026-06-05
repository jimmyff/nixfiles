---
name: plan-review
description: Comprehensively review an implementation plan or design doc — grounds every claim against the real codebase, critiques across correctness/architecture/risk/completeness lenses, adversarially verifies flaws, and returns a prioritized verdict with concrete fixes. Use when the user asks to review, critique, sanity-check, or find flaws in a plan file (e.g. "review this plan", "critique my plan at <path>", "is this plan sound?"). After reporting, it asks which items to apply, revises the plan, and emits a cold-start handoff brief to implement the revised plan in a fresh session. SKIP for authoring a new plan (that's plan mode) or reviewing code/PRs (use code-review).
---

# plan-review

Review an implementation plan or design doc: ground it against the real codebase, critique across multiple lenses, verify flaws, and return a prioritized verdict.

## Usage

`/plan-review <plan-file> [extra context]`

- `<plan-file>` — path to the markdown plan (required)
- Trailing text is extra context (goal, constraints, what to focus on)

If no path is given, ask for one. If the file is missing or unreadable, stop and say so.

## Principle

A plan review is only as good as its grounding in the real code and how honestly critical it is.

- **Ground everything.** Never critique the plan's prose in isolation — read the code it touches. The highest-value findings are where the plan's model of the *current* code is wrong (assumes behavior that doesn't hold, reinvents an existing helper, references something that moved).
- **Don't cry wolf.** Verify each flaw against the code before reporting it; tag confidence. A confident-but-wrong objection is worse than a missed nitpick.
- **Be genuinely critical.** Challenge the approach and surface stronger alternatives — but separate hard flaws (will break / won't meet the goal / violates a constraint) from design preferences from optional ideas. Don't inflate.
- **Respect the plan's frame.** Honor its stated non-goals, assumptions, and constraints — don't flag explicitly out-of-scope items as gaps. Challenge an assumption only when it's *wrong*, not merely because it's assumed.

## Effort scaling

Scale depth to the current effort level:

- **low/medium** — single grounded pass; report only high-confidence issues.
- **high** — full lens fan-out + flaw verification.
- **max** — add a completeness critic ("what's missing?") and diverse-angle blocker verification (step 4).

## Flow

### 1. Ingest & restate

1. Read the plan in full.
2. Restate its **goal, scope, and stated non-goals/assumptions in your own words** (1–3 sentences). This surfaces misreadings and frames what counts as in-scope — if you can't, the plan is underspecified; flag it (and ask one focused question if the goal is genuinely unclear).
3. Extract every concrete dependency the plan relies on: files, functions/classes, APIs, packages, data flows, and assumptions about current behavior.
4. Load conventions: the project's `AGENTS.md`/`CLAUDE.md`/`README` (walk up from the plan and cwd). The user's global guidelines are already in context — carry them into the lenses.

### 2. Ground against reality

Build a dependency map and read the key referenced files so the review shares an accurate picture of the code as it is. For each dependency, confirm symbols exist and behave as the plan assumes, and check whether the functionality already exists. For external packages/SDKs, prefer official docs/source over web search. Record each mismatch as a finding with `file:line` evidence.

### 3. Multi-lens review

First classify the plan — new feature / refactor / migration / bugfix / infra — and weight the lenses to its dominant risks (refactor → behavior-preservation; migration → data integrity & rollback; new feature → API design & tests; infra → blast radius & reversibility).

At **high/max**, spawn one Agent per lens in parallel. Give each agent the plan text, your restated goal, the grounding map, and the relevant conventions; agents may read further into the code as needed (subagents don't share your context). Each returns findings as:
`{severity, type, title, evidence (file:line), why, suggested_fix, confidence}`.

Lenses:

- **Correctness** — will these steps produce the goal? logical gaps, internal contradictions, wrong order of operations, unhandled states? for refactors, is behavior preserved?
- **Codebase grounding** — assumptions true? reinventing existing code? fits the architecture and existing patterns?
- **Architecture & simplicity** — best approach? simpler alternative? over/under-engineered (YAGNI)? DRY, separation of concerns, tech debt introduced?
- **Risk & failure modes** — what breaks? concurrency, migration, backward-compat, performance, security, data loss, reversibility, blast radius?
- **Actionability & completeness** — could a competent implementer execute this *as written* without guessing? steps concrete and ordered with dependencies satisfied? missing tests, docs, error handling, rollback, observability?
- **Convention compliance** — check against the loaded guidelines (DRY, separation of concerns, required params over defaults, no silent errors, defensive programming, <200-line files, meaningful + mockito-mocked tests) and the project's `AGENTS.md`/`CLAUDE.md`/`README`.

At **low/medium**, do this as a single pass instead of fanning out.

### 4. Prioritize & verify

1. Dedupe overlapping findings across lenses.
2. Assign severity: **Blocker** (must fix — will break or won't meet the goal) / **Major** (should fix) / **Minor** (nice to have) / **Idea** (optional / alternative).
3. For each **Blocker/Major**, spawn a skeptic Agent to *refute* it against the code. Resolve by evidence, not by default: **drop** only if the code actively refutes it; **demote** to "unverified — worth checking" if it can't be confirmed or refuted; **keep** if confirmed. At **max**, give each blocker two skeptics with different angles (e.g. "does it actually break?" vs "does the assumed code path even run?").

### 5. Report

Lead with the depth you ran at (e.g. "Reviewed at *high* — 6 lenses, blockers verified"), then output in this order; omit any empty section:

- **Verdict** — one line: Sound / Revise / Reconsider, + 2–3 sentence rationale.
- **Goal (as understood)** — your restatement, so the user can correct it.
- **Strengths** — what's good and worth keeping (brief).
- **Blocking flaws** (Blockers) — each: what, evidence `file:line`, why it breaks, suggested fix.
- **Recommendations** (Major, then Minor) — improvements worth making, ordered by severity.
- **Ideas & alternatives** (Ideas) — optional approaches worth considering.
- **Open questions** — ambiguities/assumptions to resolve before implementing; include any **demoted "unverified"** findings here.

Keep evidence concrete (`file:line`). Don't pad.

### 6. Ask & revise

After the report, run two quick interactions:

1. **Resolve open questions** — put the open questions to the user; their answers shape the revision.
2. **Choose fixes** — present the blockers and recommendations as a multi-select list, plus "all" / "none".

Then rewrite the plan file, folding in the chosen fixes and the answers. Preserve the plan's structure, voice, and intent; if a chosen fix conflicts with the stated goal, raise it rather than overriding silently. Show a short summary of what changed. If nothing is selected and no questions answered, leave the file untouched.

### 7. Handoff brief

Finish by emitting a **cold-start brief** so implementation starts in a fresh,
plan-shaped session — by now the review context is full of rejected branches and
refuted findings, a poor place to build from.

- **When.** Always emit it after step 6 (even if no edits were applied) — *unless*
  the verdict is **Reconsider** or the plan needs another round; an implementation
  handoff is premature there, so say so and skip.
- **Recommend, don't decide.** Tune one line to how much the plan changed:
  heavy/structural → "this session is desynced from the revised plan — recommend
  implementing in a fresh session"; light/none → "optional — continue here, or use
  the brief for a clean start."
- **Pointer, not payload.** The brief points at the plan; the plan is the single
  source of truth. If you're tempted to put substantive context in the brief, it
  belongs *in the plan* — fold it into step 6 instead. (Writing the brief is a
  self-sufficiency test: a cold agent must be able to execute from the plan file
  alone.)
- **Form.** A copy-paste fenced block written as the user's opening message to the
  new session — never appended to the plan file. It marks the design as settled
  (already reviewed and grounded — don't re-review) and asks for a concrete,
  ordered implementation plan re-grounded against current code (which may have
  drifted since the review):

  ```
  Implement the plan at <plan-file>.

  It's an approved design — already reviewed and grounded against the codebase.
  Treat the approach as settled; don't re-review it. Read it in full, load repo
  conventions (AGENTS.md/CLAUDE.md), then enter plan mode and produce a concrete,
  ordered implementation plan, grounding each step against the current code.
  ```

## Rules

- Read the code before asserting a flaw; cite `file:line`.
- Distinguish flaw vs. preference vs. idea — don't inflate severity.
- Never edit the plan during review/report — only after the user chooses what to apply.
- If the plan's goal is genuinely unclear, ask one focused question before reviewing rather than guessing.
- The handoff brief is chat-only and points at the plan — fold session-only context into the plan (step 6), never into the brief.
