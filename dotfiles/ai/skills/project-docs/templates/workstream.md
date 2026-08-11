---
kind: workstream
prefix: {{prefix}}
next_up: {{prefix}}-1
design: ../design/{{design_slug}}.md
---

# {{Name}}

{{purpose}}

Design: [{{design_slug}}](../design/{{design_slug}}.md).

## Sessions

<!-- The work, ordered. `- [ ] **{{prefix}}-n** — title` · `[x]` when landed. Sub-sessions are `{{prefix}}-3a`.
     IDs are permanent — they outlive this file, so never renumber and never reuse.

     A row may carry its session brief as indented prose — future tense, and mortal:

     - [ ] **{{prefix}}-n** — worked example
           Goal: one sentence. Scope: the cuts and the order — draft, not locked.
           Consumes: links into design/ — point, never restate how the system works.
           Exit: how the session knows it is done. Open: what gets decided in-session.

     Briefs hold decisions about the work and findings recorded nowhere else; how the system
     works belongs in design/ (land pre-built design there as `agreed` and link it). Fidelity
     decays with distance: full briefs only for what the next session unblocks — or one wave,
     when a sitting lands the design that specifies it. Rows further out stay thin; a brief cut
     early is a fact you must keep true, and each landing session re-trues the briefs it corrected.
     Ticking a row deletes its brief in the same edit — promote, fold corrections into the
     remaining briefs, settle the log line. A ticked row still carrying one is an audit finding. -->

- [ ] **{{prefix}}-1** — {{first_title}}

## Snags

<!-- Small things noticed in passing: too small to schedule, not blocked on anything.
     Plain bullets at column 0 — a checkbox here is a syntax error, and no IDs: snags are
     ephemeral and uncitable by design. Name files in backticks, not links — a snag often
     points at something that doesn't exist yet, and links anywhere in a file are checked.
     Cleared by deletion, never ticked — folded into the next session, or just done.
     Survived two sessions? Promote it to a session or delete it. `docs.nu snags` shows age.
     Noticed it while working elsewhere? It goes in your own tracker, same rule as the log.
     Blocked on other work? Routing needs a session row — promote it first, or delete it and
     let it be re-noticed. No tracker owns it at all? Say so in your reply; never open a TODO file.
     Keep this section even when empty; it's a write target. -->

## Log

<!-- One line per session, newest last. This is the only home for session records — never a shared file.
     Rows start at column 0; anything indented is prose and is never machine-read.

     - [ ] **{{prefix}}-1** — title
           open — carries findings not yet promoted
     - [x] **{{prefix}}-1** — title — 2026-01-01 — <markdown link to the design doc it promoted>
           settled — durable doctrine landed in design/
     - [x] **{{prefix}}-1** — title — 2026-01-01 — no doctrine
           settled — implementation-only, nothing durable to promote

     Ticked an item in another tracker? Append ` — → THEIR-ID`, repeatable. Prose mentions need no marker.

     The log is a working ledger, not a history — git keeps the history. A settled line whose
     doctrine is promoted and whose crossover tails are reconciled has discharged its duties:
     once it stops being near-term context, delete it. Never archive it anywhere. -->


## Routed gaps

<!-- Blocked work is declared here by the blocked side only — never as a note in someone else's tracker.
     Delete this section when there is nothing blocked. -->

| Blocked rows | Blocked on | Unblocks at |
|---|---|---|
