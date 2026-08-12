#!/usr/bin/env nu
# docs.nu — helper for the project-docs skill.
#
#   status   [--path <docs>] [--write]  per-tracker state; --write regenerates the README table
#   start    <tracker> [<id>]           compose that session's kickoff prompt
#   sessions <tracker> [--open]         one tracker's rows, each brief measured
#   new      <name> [--path <docs>]     scaffold a tracker from templates/workstream.md
#   audit    [--path <docs>]            advisory checks; never edits anything
#   snags    [--path <docs>]            per-tracker snag list, with age derived from git blame
#   fixture  --write [--path <dir>]     write a sample tree from templates/ (gitignored, for reading)
#   selftest                            build a throwaway tree, assert every check against expected.json
#   help                                this list
#
# `--path` defaults to `docs`, found by searching upward, so any directory in the project works.
# Bare on a terminal this opens an interactive hub; piped or redirected it prints the list above.
# `claude (docket start <tracker> <id>)` is the one-paste session opener — it composes at paste
# time, so what you paste can never be stale.
#
# Advisory by design: audit reports, it never acts. Findings are things to fix, notes are things to
# know. Every check is formulated so it cannot fire on a correctly-maintained tree in any state.

# ------------------------------------------------------------------ contract

const TRACKER_MAX = 25kb        # hard: trackers are appended to and read whole every session
const DOC_MAX = 40kb            # advisory: design/reference are re-trued in place, splitting hurts
const ACTIVITY_DAYS = 21

# Contract rows start at column 0. Anything indented is prose or a comment and is never machine-read —
# which is what lets the templates carry worked examples inside the files the script parses.
const ROW_RE = r#'^- \[(?<state>[ xX])\] \*\*(?<id>[A-Z][A-Z0-9]*-\d+[a-z]?)\*\*\s*—\s*(?<rest>.*)$'#
const LOOSE_ROW_RE = r#'^- \[[ xX]\]'#
const BRIEF_LINE_RE = r#'^\s+\S'#
const SNAG_RE = r#'^- (?<text>.+)$'#
const CROSS_RE = r#'—\s*→\s*(?<id>[A-Z][A-Z0-9]*-\d+[a-z]?)'#
const LINK_RE = r#'\]\((?<target>[^)\s]+)'#
const ID_RE = r#'^(?<prefix>[A-Z][A-Z0-9]*)-(?<num>\d+[a-z]?)$'#
const TREE_RE = r#'^\d+ blob (?<oid>[0-9a-f]+)\t(?<path>.+)$'#

const MARK_START = "<!-- docs.nu:workstreams -->"
const MARK_END = "<!-- /docs.nu:workstreams -->"

const KIND_BY_DIR = {workstreams: "workstream", design: "design", decisions: "decision", reference: "reference"}

# ------------------------------------------------------------------- reading

def skill-root []: nothing -> string { $env.FILE_PWD | path dirname }

def read-text [f: path]: nothing -> string { open --raw $f | decode utf-8 }

def slugless [f: path]: nothing -> string { $f | path basename | str replace --regex r#'\.md$'# "" }

def derive-prefix [base: string]: nothing -> string { $base | str uppercase | str replace --all --regex r#'[^A-Z0-9]'# "" }

# Line index the body starts at — past the closing `---` — or 0 when there is no frontmatter to
# close. One definition of that boundary, shared by the parser and the header extractor below.
def frontmatter-end [ls: list<string>]: nothing -> int {
    if ($ls | is-empty) or (($ls | first | str trim) != "---") { return 0 }
    let close = ($ls | skip 1 | enumerate | where {|r| ($r.item | str trim) == "---"} | get -o 0.index)
    if ($close == null) or ($close == 0) { return 0 }
    $close + 2
}

# YAML frontmatter, or {} when absent or unparseable. One parser for all four kinds.
def frontmatter [ls: list<string>]: nothing -> record {
    let end = (frontmatter-end $ls)
    if $end == 0 { return {} }
    let parsed = (try { $ls | slice 1..<($end - 1) | str join "\n" | from yaml } catch { null })
    if ($parsed | describe | str starts-with "record") { $parsed } else { {} }
}

# Everything between the frontmatter and the first `## ` — a tracker's standing context, stated
# once and true for every session it holds. The kickoff prompt is generated rather than stored
# (structure.md §Session briefs) and this is its workstream-invariant half; the `# Title` H1 rides
# along verbatim, because stripping it is a judgement the doctrine doesn't ask for.
def header-prose [ls: list<string>]: nothing -> string {
    let rest = ($ls | skip (frontmatter-end $ls))
    let end = ($rest | enumerate | where {|r| $r.item | str starts-with "## "} | get -o 0.index)
    $rest | first (if $end == null { $rest | length } else { $end })
        | skip while {|l| ($l | str trim) | is-empty}
        | reverse | skip while {|l| ($l | str trim) | is-empty} | reverse
        | str join "\n"
}

# Half-open line-index range of the body under `## <head>`, or null when the heading is absent.
# One definition of where a section ends, because the snag age derivation needs line numbers.
def section-range [ls: list<string>, head: string]: nothing -> any {
    let start = ($ls | enumerate | where {|r| $r.item | str starts-with $"## ($head)"} | get -o 0.index)
    if $start == null { return null }
    let rest = ($ls | skip ($start + 1))
    let end = ($rest | enumerate | where {|r| $r.item | str starts-with "## "} | get -o 0.index)
    {start: ($start + 1), end: (if $end == null { $ls | length } else { $start + 1 + $end })}
}

# Lines under `## <head>` up to the next `## `.
def section [ls: list<string>, head: string]: nothing -> list<string> {
    let r = (section-range $ls $head)
    if $r == null { [] } else { $ls | slice $r.start..<$r.end }
}

def rows [ls: list<string>]: nothing -> table {
    $ls | parse --regex $ROW_RE | update state {|r| if ($r.state | str lowercase) == "x" {"x"} else {" "}}
}

# Every `## Sessions` row with the indented prose beneath it — the row's session brief. One walker,
# because the staleness check and the generated kickoff prompt must agree on where a brief starts
# and stops. Blank lines don't end a row's scope (a brief may hold paragraphs) and are kept so the
# paragraph breaks survive; trailing ones are trimmed. Any other column-0 line does end it — a
# `## Sessions` section may carry a blockquote or a note between rows, and splicing one of those
# into a brief would put somebody else's prose in a session prompt.
def session-blocks [ls: list<string>]: nothing -> table {
    let r = (section-range $ls "Sessions")
    if $r == null { return [] }
    let acc = ($ls | slice $r.start..<$r.end | reduce --fold {out: [], cur: null} {|l, acc|
        let row = ($l | parse --regex $ROW_RE)
        if ($row | is-not-empty) {
            let it = ($row | first)
            let started = {
                id: $it.id
                state: (if ($it.state | str lowercase) == "x" {"x"} else {" "})
                title: ($it.rest | str trim)
                brief: []
            }
            (flush-block $acc) | update cur $started
        } else if $acc.cur == null {
            $acc
        } else if ($l =~ $BRIEF_LINE_RE) or (($l | str trim) | is-empty) {
            $acc | update cur ($acc.cur | update brief ($acc.cur.brief | append $l))
        } else {
            flush-block $acc
        }
    })
    (flush-block $acc).out
}

def flush-block [acc: record]: nothing -> record {
    if $acc.cur == null { return {out: $acc.out, cur: null} }
    let brief = ($acc.cur.brief | reverse | skip while {|l| ($l | str trim) | is-empty} | reverse)
    {out: ($acc.out | append ($acc.cur | update brief $brief)), cur: null}
}

# Checkbox lines that don't match the contract — surfaced so a mis-shaped tracker never fails silently.
def unparsed [ls: list<string>]: nothing -> int {
    ($ls | parse --regex $LOOSE_ROW_RE | length) - ($ls | parse --regex $ROW_RE | length)
}

# Snags with their 1-based line numbers, so age can be joined from git blame without re-reading.
def snag-rows [ls: list<string>]: nothing -> table {
    let r = (section-range $ls "Snags")
    if $r == null { return [] }
    $ls | enumerate | slice $r.start..<$r.end
        | each {|e| $e.item | parse --regex $SNAG_RE | each {|m| {line: ($e.index + 1), text: $m.text}}}
        | flatten
}

# 1-based line numbers of the contract rows under `## <head>`.
def row-lines [ls: list<string>, head: string]: nothing -> list<int> {
    let r = (section-range $ls $head)
    if $r == null { return [] }
    $ls | enumerate | slice $r.start..<$r.end
        | where {|e| $e.item =~ $ROW_RE} | each {|e| $e.index + 1}
}

def split-id [id: string]: nothing -> record {
    let p = ($id | parse --regex $ID_RE)
    if ($p | is-empty) { {prefix: "", num: ""} } else { $p | first }
}

def read-doc [f: path, docs: path]: nothing -> record {
    let ls = (read-text $f | lines)
    let fm = (frontmatter $ls)
    let dir = ($f | path dirname | path basename)
    let base = (slugless $f)
    let sess = (section $ls "Sessions")
    let log = (section $ls "Log")
    let snag = (section $ls "Snags")
    {
        path: ($f | path expand --no-symlink)
        rel: ($f | path relative-to ($docs | path dirname))
        base: $base
        kind: ($fm | get -o kind | default ($KIND_BY_DIR | get -o $dir | default "other"))
        size: (ls -a $f | first | get size)
        prefix: ($fm | get -o prefix | default (derive-prefix $base))
        next_up: ($fm | get -o next_up | default "—")
        header: (header-prose $ls)
        text: ($ls | str join "\n")
        sessions: (rows $sess)
        log: (rows $log)
        log_lines: (row-lines $ls "Log")
        snags: (snag-rows $ls)
        # Snags are counted too: a checkbox there parses as a snag, so without this a ticked
        # snag would be both immortal and invisible to every check.
        loose: ((unparsed $sess) + (unparsed $log) + (unparsed $snag))
    }
}

def load-docs [docs: path]: nothing -> table {
    glob ($docs | path join "**" "*.md") | each {|f| read-doc $f $docs}
}

# Relative link targets that should resolve on disk. Externals and bare anchors are not our business,
# and neither are placeholders — `img/<screen>.webp` in a template file is a correct link to nothing.
def local-links [d: record]: nothing -> list<string> {
    $d.text | parse --regex $LINK_RE | get target
    | where {|t| not ($t =~ '://') and not ($t | str starts-with "#") and not ($t | str starts-with "mailto:")}
    | where {|t| not ($t =~ '[<>{}]')}
    | each {|t| $t | split row "#" | first | split row "?" | first}
    | where {|t| $t | is-not-empty}
    | each {|t| $d.path | path dirname | path join $t | path expand --no-symlink}
}

# ---------------------------------------------------------------------- git

def repo-root [dir: path]: nothing -> any {
    let r = (^git -C $dir rev-parse --show-toplevel | complete)
    if $r.exit_code != 0 { null } else { $r.stdout | str trim | path expand }
}

# Commits touching the trackers that live on some branch but are not in our history. Derived, never
# stored: a lock written on branch A is invisible from branch B until they merge, which is the moment
# it stops mattering. Blind spot, stated rather than hidden: uncommitted work elsewhere is unseeable.
def other-branch-activity [root: string, ws_rel: string]: nothing -> table {
    let r = (^git -C $root log --all --not HEAD --since $"($ACTIVITY_DAYS) days ago"
        --pretty=format:'@@REC@@%h|%aI' --name-only -- $ws_rel | complete)
    if $r.exit_code != 0 { return [] }
    $r.stdout | split row "@@REC@@" | where {|c| $c | is-not-empty}
    | each {|c|
        let ls = ($c | lines | where {|l| $l | is-not-empty})
        if ($ls | is-empty) { null } else {
            let when = ($ls | first | split row "|" | last)
            $ls | skip 1 | each {|p| {file: $p, when: $when}}
        }
    } | compact | flatten
    | group-by file
    | items {|k, v| {file: $k, commits: ($v | length), latest: ($v | get when | sort | last | str substring 0..9)}}
}

# Line number → author epoch, for deriving snag age. Age is never stored, for the same reason the
# lock isn't: a written date is a fact with two homes. Uncommitted lines blame as an all-zero sha and
# are dropped, so every degradation — no repo, untracked file, squashed history, a reworded snag —
# lands on "brand new" rather than on a number that would push a false promotion.
def blame-times [root: string, f: path]: nothing -> record {
    let r = (^git -C $root blame --line-porcelain -- $f | complete)
    if $r.exit_code != 0 { return {} }
    let ls = ($r.stdout | lines)
    let heads = ($ls | parse --regex r#'^(?<sha>[0-9a-f]{40}) \d+ (?<final>\d+)'#)
    let times = ($ls | parse --regex r#'^author-time (?<t>\d+)'#)
    $heads | zip $times | where {|p| ($p.0.sha | str replace --all "0" "") | is-not-empty}
        | reduce --fold {} {|p, acc| $acc | insert $p.0.final ($p.1.t | into int)}
}

# Session declarations at every branch tip. Blobs are deduped by object id first: identical content
# across refs cannot collide, which is what keeps stale backup branches from firing forever.
def sessions-across-refs [root: string, ws_rel: string]: nothing -> table {
    let refs = (^git -C $root for-each-ref --format '%(refname:short)' refs/heads | complete)
    if $refs.exit_code != 0 { return [] }
    let entries = ($refs.stdout | lines | where {|r| $r | is-not-empty} | each {|ref|
        let t = (^git -C $root ls-tree -r $ref -- $ws_rel | complete)
        if $t.exit_code != 0 { [] } else {
            $t.stdout | lines | parse --regex $TREE_RE | each {|e| {ref: $ref, oid: $e.oid, file: $e.path}}
        }
    } | flatten)
    if ($entries | is-empty) { return [] }
    let byOid = ($entries | get oid | uniq | each {|oid|
        let b = (^git -C $root cat-file blob $oid | complete)
        let ls = (if $b.exit_code != 0 { [] } else { $b.stdout | lines })
        {oid: $oid, rows: (rows (section $ls "Sessions")), prefix: ((frontmatter $ls) | get -o prefix)}
    } | reduce --fold {} {|it, acc| $acc | insert $it.oid $it})
    $entries | each {|e|
        let blob = ($byOid | get $e.oid)
        let base = (slugless $e.file)
        $blob.rows | each {|r| {
            ref: $e.ref, file: $base, id: $r.id, title: ($r.rest | str trim)
            prefix: ($blob.prefix | default (derive-prefix $base))
        }}
    } | flatten
}

# -------------------------------------------------------------------- checks

def emit [check: string, severity: string, path: string, detail: string]: nothing -> record {
    {check: $check, severity: $severity, path: $path, detail: $detail}
}

def check-size [all: table]: nothing -> table {
    $all | each {|d|
        if $d.kind == "workstream" and $d.size > $TRACKER_MAX {
            emit "size" "finding" $d.rel $"($d.size) over ($TRACKER_MAX) — trackers are read whole every session. Harvest before splitting: executed briefs, settled log lines past their use, log records grown into sections, design living in the tracker; split by sub-stream only if the live plan is over"
        } else if ($d.kind in ["design" "reference"]) and $d.size > $DOC_MAX {
            emit "size" "note" $d.rel $"($d.size) over ($DOC_MAX) — re-trued in place, so splitting manufactures boundary-straddling facts; judgement call"
        }
    } | compact
}

def check-links [all: table]: nothing -> table {
    $all | each {|d|
        local-links $d | where {|t| not ($t | path exists)} | each {|t|
            emit "dead-link" "finding" $d.rel $"broken link → ($t | path basename)"
        }
    } | flatten
}

# Repo-wide, because docs are routinely linked only from a root CLAUDE.md / AGENTS.md / README.md.
def check-orphans [all: table, docs: path, root: any]: nothing -> table {
    let repoMd = (if $root == null { glob ($docs | path join "**" "*.md") } else {
        let r = (^git -C $root ls-files '*.md' | complete)
        if $r.exit_code != 0 { glob ($docs | path join "**" "*.md") } else {
            $r.stdout | lines | where {|p| $p | is-not-empty} | each {|p| $root | path join $p}
        }
    })
    let linked = ($repoMd | where {|p| $p | path exists} | each {|p|
        let self = ($p | path expand --no-symlink)
        local-links {path: $self, text: (read-text $p)} | where {|t| $t != $self}
    } | flatten | uniq)
    let entry = ($docs | path join "README.md" | path expand --no-symlink)
    $all | where {|d| $d.path != $entry and $d.path not-in $linked}
        | each {|d| emit "orphan" "finding" $d.rel "linked from nowhere in the repo — link it or delete it"}
}

def check-closure [trackers: table]: nothing -> table {
    $trackers | each {|t|
        # Guarded against the empty tracker, where "every item is [x]" is vacuously true.
        if ($t.sessions | is-not-empty) and (($t.sessions | where state == " " | length) == 0) {
            emit "closure" "note" $t.rel "every session ticked — candidate for closure, needs approval. Harvest to design/ and decisions/, then delete on main"
        }
    } | compact
}

def check-open-log [trackers: table]: nothing -> table {
    $trackers | each {|t|
        let open = ($t.log | where state == " ")
        if ($open | is-not-empty) {
            emit "open-log" "note" $t.rel $"findings not yet promoted: ($open | get id | str join ', ')"
        }
    } | compact
}

# Only `→ ID` tails are read. Prose citations of another workstream's IDs are deliberately not
# findings: invariant 1 encourages linking over restating, and a check that punished it would train
# agents to stop linking.
def check-crossover [trackers: table]: nothing -> table {
    let byPrefix = ($trackers | reduce --fold {} {|t, acc| $acc | insert $t.prefix $t})
    $trackers | each {|t|
        $t.log | each {|r|
            $r.rest | parse --regex $CROSS_RE | get id | each {|cid|
                let p = (split-id $cid).prefix
                let target = ($byPrefix | get -o $p)
                if $p == $t.prefix { null } else if $target == null {
                    emit "crossover" "finding" $t.rel $"($r.id) cites ($cid), but no tracker declares prefix ($p)"
                } else {
                    let hit = ($target.sessions | where id == $cid)
                    if ($hit | is-empty) {
                        emit "crossover" "finding" $t.rel $"($r.id) cites ($cid), but ($target.base).md declares no such session"
                    } else if (($hit | first | get state) == " ") {
                        emit "crossover" "finding" $t.rel $"($r.id) cites ($cid), still open in ($target.base).md — reconcile at merge"
                    }
                }
            } | compact
        } | flatten
    } | flatten
}

def check-collisions [trackers: table, docs: path, root: any]: nothing -> table {
    let dir = ($docs | path basename)
    let local = ($trackers | group-by prefix | items {|p, ts|
        if ($ts | length) > 1 {
            emit "collision" "finding" ($ts | get rel | first) $"prefix ($p) declared by ($ts | length) trackers: ($ts | get base | str join ', ')"
        }
    } | compact)
    if $root == null {
        return ($local | append (emit "collision" "note" $dir "cross-branch check skipped — not a git repo"))
    }
    let across = (sessions-across-refs $root (($docs | path join "workstreams") | path relative-to $root))
    if ($across | is-empty) { return $local }
    let idClash = ($across | group-by id | items {|id, rs|
        if (($rs | get title | uniq | length) > 1) {
            emit "collision" "finding" $"($dir)/workstreams/($rs | get file | first).md" $"($id) declared with different titles on ($rs | get ref | uniq | str join ', ') — a rename or a double allocation; reconcile before merge"
        }
    } | compact)
    let prefixClash = ($across | select prefix file | uniq | group-by prefix | items {|p, rs|
        if ($rs | length) > 1 {
            emit "collision" "finding" $"($dir)/workstreams/($rs | get file | first).md" $"prefix ($p) claimed by ($rs | get file | str join ', ') across branches"
        }
    } | compact)
    $local | append $idClash | append $prefixClash
}

# Ticked rows whose brief outlived them, with the surviving prose lines counted.
def leftover-briefs [ls: list<string>]: nothing -> table {
    session-blocks $ls | where state == "x"
        | each {|b| {id: $b.id, lines: ($b.brief | where {|l| $l =~ $BRIEF_LINE_RE} | length)}}
        | where lines > 0
}

# A brief dies when its row ticks, so anything left under one has outlived its session — the one
# staleness check a brief affords, because the tick is a mechanical clearing event. Unticked briefs
# are deliberately unchecked (the snags reasoning: thresholds manufacture false positives), and
# `## Log` rows are exempt — a settled log entry legitimately carries a prose line.
def check-brief [trackers: table]: nothing -> table {
    $trackers | each {|t|
        leftover-briefs ($t.text | lines) | each {|b|
            emit "brief" "finding" $t.rel $"($b.lines) lines of brief under ticked ($b.id) — a brief dies when its row ticks: promote to design/ or decisions/, then delete"
        }
    } | flatten
}

def check-syntax [trackers: table]: nothing -> table {
    $trackers | each {|t|
        if $t.loose > 0 {
            emit "syntax" "note" $t.rel $"($t.loose) checkbox rows don't match the contract — invisible to every other check"
        }
    } | compact
}

def audit-findings [docs: path]: nothing -> table {
    let all = (load-docs $docs)
    let trackers = ($all | where kind == "workstream")
    let root = (repo-root $docs)
    (check-size $all)
    | append (check-links $all)
    | append (check-orphans $all $docs $root)
    | append (check-closure $trackers)
    | append (check-collisions $trackers $docs $root)
    | append (check-open-log $trackers)
    | append (check-crossover $trackers)
    | append (check-brief $trackers)
    | append (check-syntax $trackers)
}

# ------------------------------------------------------------------ commands

def "main audit" [--path: string = "docs"] {
    let docs = (require-docs $path)
    let out = (audit-findings $docs)
    print --stderr $"(ansi dark_gray)Cannot see: semantic duplication · a doc gone stale against the code it describes · uncommitted work in other worktrees. A clean audit is not a healthy tree.(ansi reset)"
    if ($out | is-empty) { print --stderr $"(ansi green)no findings(ansi reset)" }
    $out
}

# `since` is sessions logged after the snag appeared — the instrument for the two-session rule.
# `require-docs` first is the point: without it a mistyped path prints zero rows and exits 0, a silent
# error on the one command whose whole job is answering "did I miss anything".
def "main snags" [--path: string = "docs"] {
    let docs = (require-docs $path)
    let root = (repo-root $docs)
    if $root == null { print --stderr $"(ansi yellow)note(ansi reset) age not derived — not a git repo" }
    load-docs $docs | where kind == "workstream" | sort-by base | each {|t|
        if ($t.snags | is-empty) { [] } else {
            let bt = (if $root == null { {} } else { blame-times $root $t.path })
            let logT = ($t.log_lines | each {|l| $bt | get -o ($l | into string)} | compact)
            $t.snags | each {|s|
                let at = ($bt | get -o ($s.line | into string))
                {
                    tracker: $t.base
                    since: (if $at == null { 0 } else { $logT | where {|x| $x > $at} | length })
                    snag: $s.text
                }
            }
        }
    } | flatten
}

def "main status" [--path: string = "docs", --write] {
    let docs = (require-docs $path)
    let trackers = (load-docs $docs | where kind == "workstream" | sort-by base)
    let root = (repo-root $docs)
    let activity = (if $root == null { [] } else {
        other-branch-activity $root (($docs | path join "workstreams") | path relative-to $root)
    })
    let out = ($trackers | each {|t|
        let key = (if $root == null { "" } else { $t.path | path relative-to $root })
        let a = ($activity | where file == $key)
        {
            tracker: $t.base
            prefix: $t.prefix
            next_up: $t.next_up
            open: $"($t.sessions | where state == ' ' | length) / ($t.sessions | length)"
            size: $t.size
            other_branches: (if ($a | is-empty) {"—"} else {
                let h = ($a | first); $"($h.commits) commits to ($h.latest)"
            })
        }
    })
    if $write { write-readme-table $docs $trackers }
    $out
}

# Trackers are addressed by base name — the same string `status` prints in its `tracker` column.
def tracker-file [docs: path, name: string]: nothing -> path {
    let f = ($docs | path join "workstreams" $"($name).md")
    if not ($f | path exists) {
        let have = (glob ($docs | path join "workstreams" "*.md") | each {|p| slugless $p} | sort)
        error make {msg: $"no tracker ($name) — ($docs | path basename)/workstreams has: ($have | str join ', ')"}
    }
    $f
}

# One tracker's session rows, document order preserved. `is_next` is a bool and deliberately not
# named `next_up`: `status` already uses that name for the ID *string*, and one name must not carry
# two types. Exists so the hub's picker is plain dispatch, and it reads well on its own.
def "main sessions" [tracker: string, --path: string = "docs", --open] {
    let docs = (require-docs $path)
    let d = (read-doc (tracker-file $docs $tracker) $docs)
    let out = (session-blocks ($d.text | lines) | each {|b| {
        id: $b.id
        state: $b.state
        title: $b.title
        brief_lines: ($b.brief | where {|l| $l =~ $BRIEF_LINE_RE} | length)
        is_next: ($b.id == ($d.next_up | into string))
    }})
    if $open { $out | where state == " " } else { $out }
}

# Which session a bare `start` means. An absent `next_up` is normal rather than a defect, so it
# passes silently — warning on it would train you to ignore the warning that matters, which is a
# `next_up` naming a row that has already landed or never existed.
def pick-session [d: record, blocks: table, session: any]: nothing -> record {
    if $session != null {
        let hit = ($blocks | where id == $session)
        if ($hit | is-empty) {
            error make {msg: $"($d.rel) has no session ($session) — open: ($blocks | where state == ' ' | get id | str join ', ')"}
        }
        return ($hit | first)
    }
    let open = ($blocks | where state == " ")
    if ($open | is-empty) {
        error make {msg: $"($d.rel): every session ticked — nothing to start; close the tracker"}
    }
    let first = ($open | first)
    let next = ($d.next_up | into string)
    if ($next == "—") or ($next | is-empty) { return $first }
    let named = ($blocks | where id == $next)
    if ($named | is-empty) {
        print --stderr $"(ansi yellow)note(ansi reset) next_up ($next) matches no session row — starting ($first.id)"
        return $first
    }
    let it = ($named | first)
    if $it.state == " " { return $it }
    print --stderr $"(ansi yellow)note(ansi reset) next_up ($next) is already ticked — starting ($first.id)"
    $first
}

# Common indent measured over non-blank lines only: briefs hold blank lines between paragraphs, so
# a prefix taken over every line is always "" and nothing de-indents. The width varies by tracker
# as well (2 in one, 6 in another), so a fixed strip is equally wrong.
def dedent [ls: list<string>]: nothing -> string {
    let body = ($ls | where {|l| ($l | str trim) | is-not-empty})
    if ($body | is-empty) { return "" }
    let n = ($body | each {|l| ($l | str length) - ($l | str trim --left | str length)} | math min)
    $ls | each {|l| if (($l | str trim) | is-empty) { "" } else { $l | str substring $n.. }} | str join "\n"
}

# The kickoff prompt, generated rather than stored (structure.md §Session briefs): the tracker's
# header prose plus the row's brief, which is exactly what the brief is written to complement.
# Returned as a string and never written to a file — `claude (docket start wiring W-1d)` composes
# it at paste time, so what you paste cannot be stale, and `| pbcopy` gets the clipboard for free.
def "main start" [tracker: string, session?: string, --path: string = "docs"] {
    let docs = (require-docs $path)
    let d = (read-doc (tracker-file $docs $tracker) $docs)
    let blocks = (session-blocks ($d.text | lines))
    if ($blocks | is-empty) { error make {msg: $"($d.rel) declares no sessions"} }
    let pick = (pick-session $d $blocks $session)
    let brief = (dedent $pick.brief)

    if ($d.header | str trim | is-empty) {
        print --stderr $"(ansi yellow)note(ansi reset) ($d.rel) carries no header prose — the prompt is the brief alone"
    } else if ($d.header | str contains "{{") {
        print --stderr $"(ansi yellow)note(ansi reset) ($d.rel) header still holds {{...}} placeholders from `new`"
    }
    if ($brief | str trim | is-empty) {
        print --stderr $"(ansi yellow)note(ansi reset) ($pick.id) carries no brief — scope it in the tracker first"
    }

    # A pointer, never a restatement: structure.md and templates/workstream.md already own the
    # tick/promote/settle rules, and a third copy here is the one nobody would re-true.
    let footer = ([
        "---"
        "Read the Consumes links before writing code — point at design docs, never restate them."
        "Close this session per the project-docs skill (structure.md §Session briefs)."
    ] | str join "\n")

    let flag = (if $path == "docs" { "" } else { $" --path ($path)" })
    print --stderr $"(ansi green)start(ansi reset) claude \(docket start ($tracker) ($pick.id)($flag))"

    [
        $"Tracker: ($d.path) — session ($pick.id)."
        $d.header
        $"## Session: ($pick.id) — ($pick.title)"
        $brief
        $footer
    ] | where {|p| ($p | str trim) | is-not-empty} | str join "\n\n"
}

# Ancestors of `from`, nearest first, stopping at `ceiling` or the filesystem root.
def ancestors [from: path, ceiling: path]: nothing -> list<string> {
    mut cur = ($from | path expand)
    mut out = []
    loop {
        $out = ($out | append $cur)
        let parent = ($cur | path dirname)
        if ($cur == $ceiling) or ($parent == $cur) { break }
        $cur = $parent
    }
    $out
}

# The docs tree to work on, or null. Searching upward is **default-path only**: an explicit --path
# is honoured exactly, so a typo stays a hard error instead of silently auditing some ancestor's
# tree. The walk requires a `workstreams/` inside, and stops at the repo root (or $HOME) because
# past that the next `docs/` found belongs to somebody else's project.
def resolve-docs [path: string]: nothing -> any {
    if ($path | str trim | is-empty) { error make {msg: "--path is empty"} }
    let direct = ($path | path expand)
    if ($direct | path exists) { return $direct }
    if $path != "docs" { return null }
    let from = (pwd)
    let root = (repo-root $from)
    ancestors $from (if $root == null { $nu.home-dir } else { $root })
        | each {|d| $d | path join "docs"}
        | where {|d| $d | path join "workstreams" | path exists}
        | get -o 0
}

def require-docs [path: string]: nothing -> path {
    let docs = (resolve-docs $path)
    if $docs == null {
        error make {msg: (if $path != "docs" {
            $"no such directory: ($path | path expand)"
        } else {
            $"no docs/ with a workstreams/ here or in any parent of (pwd)"
        })}
    }
    $docs
}

def write-readme-table [docs: path, trackers: table] {
    let readme = ($docs | path join "README.md")
    if not ($readme | path exists) { error make {msg: $"($readme) does not exist — copy templates/docs-readme.md first"} }
    let ls = (read-text $readme | lines)
    let a = ($ls | enumerate | where {|r| ($r.item | str trim) == $MARK_START} | get -o 0.index)
    let b = ($ls | enumerate | where {|r| ($r.item | str trim) == $MARK_END} | get -o 0.index)
    if ($a == null) or ($b == null) or ($b < $a) {
        error make {msg: $"($readme) is missing the ($MARK_START) / ($MARK_END) markers"}
    }
    let body = (if ($trackers | is-empty) { ["", "_None._", ""] } else {
        ["", "| Workstream | Next up | Open |", "|---|---|---|"]
        | append ($trackers | sort-by base | each {|t|
            $"| [($t.base)]\(workstreams/($t.base).md) | ($t.next_up) | ($t.sessions | where state == ' ' | length) / ($t.sessions | length) |"
        }) | append [""]
    })
    ($ls | first ($a + 1)) | append $body | append ($ls | skip $b) | str join "\n" | $"($in)\n" | save -f $readme
    print --stderr $"(ansi green)updated(ansi reset) ($readme)"
}

# `resolve-docs` rather than `require-docs`: this is the one command that legitimately runs against
# a tree that isn't there yet, so a miss falls back to the literal path and creates it.
def "main new" [name: string, --path: string = "docs", --prefix: string = "", --design: string = ""] {
    let dir = ((resolve-docs $path | default ($path | path expand)) | path join "workstreams")
    let target = ($dir | path join $"($name).md")
    if ($target | path exists) { error make {msg: $"($target) already exists"} }
    let pre = (if ($prefix | is-empty) { derive-prefix $name } else { $prefix })
    mkdir $dir
    render (read-text (skill-root | path join "templates" "workstream.md")) {
        prefix: $pre
        Name: ($name | str replace --all "-" " " | str capitalize)
        purpose: "{{purpose}}"
        first_title: "{{first_title}}"
        design_slug: $design
    } | save -f $target
    print --stderr $"(ansi green)created(ansi reset) ($target) — prefix ($pre). Fill the {{...}} placeholders."
    $target
}

# Substitute {{keys}}. A key given as "" drops every line that mentions it, so a tracker with no
# design doc yet doesn't ship a link to a file that isn't there.
def render [tpl: string, vars: record]: nothing -> string {
    let dropped = ($vars | items {|k, v| if ($v | is-empty) { $"{{($k)}}" } else { null }} | compact)
    let kept = ($tpl | lines | where {|l| $dropped | all {|d| not ($l | str contains $d)}})
    $vars | items {|k, v| {k: $k, v: $v}} | reduce --fold ($kept | str join "\n") {|it, acc|
        $acc | str replace --all $"{{($it.k)}}" $it.v
    } | str replace --all --regex r#'\n{3,}'# "\n\n" | $"($in)\n"
}

# ------------------------------------------------------------------ fixture

# Generated from the templates, never hand-written beside them: a hand-written fixture freezes a
# grammar the templates don't actually produce, which is how a green selftest starts lying. It is
# also never committed — built fresh each run, it cannot go stale, so there is nothing to diff.
def build-fixture [dest: path] {
    let tpl = (skill-root | path join "templates")
    let docs = ($dest | path join "docs")
    rm -rf $dest
    mkdir ($docs | path join "workstreams") ($docs | path join "design") ($docs | path join "decisions")

    (render (read-text ($tpl | path join "docs-readme.md")) {
        Name: "Fixture"
        purpose: "A generated tree carrying one instance of each audit fault, plus a healthy tracker that must stay silent."
    } | save -f ($docs | path join "README.md"))

    # Healthy: open sessions, an open log entry, a prose citation of a foreign ID, two snags, and a
    # realistic brief under an unticked row that must stay silent. Zero findings, ever. The snags are
    # deliberately link-free prose: one linking a missing file would add a dead-link finding, and one
    # linking orphan.md would remove the orphan finding — either way the fixture would stop proving
    # that snags are purely additive.
    (tracker $tpl "HEALTHY" "Healthy" "content" "wire the first screen"
        ["- [ ] **HEALTHY-2** — second session"
         "      Goal: wire the second screen onto the seam the first one landed."
         "      Scope: the list pane only — the detail pane is HEALTHY-3's; draft, not locked."
         "      Consumes: [content](../design/content.md) — point, never restate."
         "      Exit: the list renders from the real store; analyzer clean."]
        ["- [x] **HEALTHY-1** — first session — 2026-01-01 — [why](../design/content.md)"
         "- [ ] **HEALTHY-3** — third session"
         "  Shares the seam CROSS-1 uses; nothing to restate here."]
        --snags ["- the first screen still names the widget it replaced — rename on the next pass"
                 "- two colour constants say the same thing; fold one into the other"]
    ) | save -f ($docs | path join "workstreams" "healthy.md")

    (tracker $tpl "CLOSING" "Closing" "content" "the only session" []
        ["- [x] **CLOSING-1** — the only session — 2026-01-01 — no doctrine"]
    | str replace "- [ ] **CLOSING-1**" "- [x] **CLOSING-1**") | save -f ($docs | path join "workstreams" "closing.md")

    ((tracker $tpl "HUGE" "Huge" "content" "one session" [] []) + "\n"
        + (1..420 | each {|i| $"Line ($i) of filler. A tracker this size is no longer read whole, which is the entire reason for the cap."} | str join "\n") + "\n"
    ) | save -f ($docs | path join "workstreams" "huge.md")

    (tracker $tpl "CROSS" "Cross" "content" "one session" []
        ["- [x] **CROSS-1** — ticked something elsewhere — 2026-01-01 — no doctrine — → HEALTHY-9"]
    ) | save -f ($docs | path join "workstreams" "crossover.md")

    (tracker $tpl "BROKEN" "Broken" "content" "one session" []
        ["- [x] **BROKEN-1** — links into the void — 2026-01-01 — [why](../design/gone.md)"]
    ) | save -f ($docs | path join "workstreams" "broken.md")

    # A ticked row that kept its brief — the brief check's one fault. STALE-1 stays open so the
    # closure note cannot fire beside it and muddy what this tracker proves.
    (tracker $tpl "STALE" "Stale" "content" "a thin row, still open"
        ["- [x] **STALE-2** — landed, brief left behind"
         "      Goal: this prose should have been deleted when the row ticked."
         "      Scope: three indented lines, exactly the shape the check reads."
         "      Exit: the audit names it."]
        ["- [x] **STALE-2** — landed, brief left behind — 2026-01-01 — no doctrine"]
    ) | save -f ($docs | path join "workstreams" "stale.md")

    (render (read-text ($tpl | path join "design.md")) {
        created: "2026-01-01", Name: "Content"
        purpose: "The design every fixture tracker points at. Links [0001](../decisions/0001-example.md) and [fat](fat.md) so neither is an orphan."
    }) | save -f ($docs | path join "design" "content.md")

    ((render (read-text ($tpl | path join "design.md")) {created: "2026-01-01", Name: "Fat", purpose: "Over the advisory cap."}) + "\n"
        + (1..640 | each {|i| $"Paragraph ($i). Design docs are re-trued in place, so this cap is advisory, not a split order."} | str join "\n") + "\n"
    ) | save -f ($docs | path join "design" "fat.md")

    (render (read-text ($tpl | path join "design.md")) {created: "2026-01-01", Name: "Orphan", purpose: "Linked from nowhere."})
        | save -f ($docs | path join "design" "orphan.md")
    (render (read-text ($tpl | path join "decision.md")) {created: "2026-01-01", number: "0001", Name: "Example"})
        | save -f ($docs | path join "decisions" "0001-example.md")

    main status --path $docs --write | ignore
}

def tracker [tpl: path, prefix: string, name: string, design: string, first: string, sessions: list<string>, log: list<string>, --snags: list<string> = []]: nothing -> string {
    let base = (render (read-text ($tpl | path join "workstream.md")) {
        prefix: $prefix, Name: $name, design_slug: $design
        purpose: $"The ($name | str lowercase) tracker."
        first_title: $first
    })
    insert-rows (insert-rows (insert-rows $base "Sessions" $sessions) "Snags" $snags) "Log" $log
}

# Append contract rows at the end of a section, preserving the template's own shape above them.
def insert-rows [text: string, head: string, extra: list<string>]: nothing -> string {
    if ($extra | is-empty) { return $text }
    let ls = ($text | lines)
    let start = ($ls | enumerate | where {|r| $r.item | str starts-with $"## ($head)"} | get -o 0.index)
    if $start == null { return $text }
    let rel = ($ls | skip ($start + 1) | enumerate | where {|r| $r.item | str starts-with "## "} | get -o 0.index)
    let cut = (if $rel == null { $ls | length } else { $start + 1 + $rel })
    let above = ($ls | first $cut | reverse | skip while {|l| ($l | str trim) == ""} | reverse)
    # Join an existing row list tightly; otherwise leave the blank line the template's prose needs.
    let gap = (if ($above | last | str starts-with "- [") { [] } else { [""] })
    ($above | append $gap | append $extra | append "" | append ($ls | skip $cut)) | str join "\n"
}

# For reading, not for testing — selftest builds its own copy in $TMPDIR. tests/fixture/ is gitignored.
def "main fixture" [--write, --path: string = ""] {
    if not $write { error make {msg: "refusing to run without --write (it replaces the destination)"} }
    let dest = (if ($path | is-empty) { skill-root | path join "tests" "fixture" } else { $path | path expand })
    build-fixture $dest
    print --stderr $"(ansi green)regenerated(ansi reset) ($dest)"
    glob ($dest | path join "docs" "**" "*.md") | each {|f| {file: ($f | path relative-to $dest), size: (ls -a $f | first | get size)}}
}

# ----------------------------------------------------------------- selftest

def "main selftest" [] {
    let root = (skill-root)
    let tmp = ($nu.temp-dir | path expand | path join "project-docs-selftest")
    let run = ($tmp | path join "run")
    rm -rf $tmp

    # Built fresh from templates/ on every run and thrown away after. Nothing is committed, so the
    # fixture cannot drift out of step with the grammar it is meant to exercise.
    build-fixture $run
    let git_ok = (try { seed-repo $run; true } catch { false })

    let got = (audit-findings ($run | path join "docs"))
    let want = (open ($root | path join "tests" "expected.json"))

    # Per check, not "and nothing else": a tree rich enough to hold every fault trips others too.
    # The two git-derived checks skip rather than fail when git is unavailable — a skip that reads as
    # a pass is how a suite quietly stops testing anything.
    let results = ($want | columns | append ($got | get check) | uniq | sort | each {|c|
        let g = ($got | where check == $c | select severity path | sort-by path severity)
        let w = (($want | get -o $c | default []) | select severity path | sort-by path severity)
        if (not $git_ok) and $c == "collision" {
            {check: $c, status: "skip", want: $w, got: $g}
        } else {
            {check: $c, status: (if $g == $w { "ok" } else { "FAIL" }), want: $w, got: $g}
        }
    })
    $results | each {|r|
        match $r.status {
            "ok" => { print $"(ansi green)ok(ansi reset)   ($r.check) — ($r.got | length) rows" }
            "skip" => { print $"(ansi yellow)skip(ansi reset) ($r.check) — needs git" }
            _ => {
                print $"(ansi red)FAIL(ansi reset) ($r.check)"
                print $"       want: ($r.want | each {|x| $'($x.severity) ($x.path)'} | str join '; ')"
                print $"       got:  ($r.got | each {|x| $'($x.severity) ($x.path)'} | str join '; ')"
            }
        }
    } | ignore

    # Concurrency is derived, not stored — the whole reason there is no lock. Assert the derivation
    # really sees a sibling branch's commit, from a worktree that never checked that branch out.
    let derived = (if $git_ok {
        (other-branch-activity $run "docs/workstreams" | where file =~ 'crossover' | is-not-empty)
    } else { true })
    if not $git_ok { print $"(ansi yellow)skip(ansi reset) cross-branch activity — needs git" } else if $derived {
        print $"(ansi green)ok(ansi reset)   cross-branch activity derived from git"
    } else {
        print $"(ansi red)FAIL(ansi reset) other-branch-activity saw nothing on a repo with a divergent branch"
    }

    # The regression guard: a correctly-maintained tracker produces zero findings, ever.
    let noise = ($got | where severity == "finding" and path =~ 'healthy')
    if ($noise | is-empty) { print $"(ansi green)ok(ansi reset)   healthy tracker — zero findings" } else {
        print $"(ansi red)FAIL(ansi reset) healthy tracker produced findings:"
        $noise | each {|n| print $"       ($n.check): ($n.detail)"} | ignore
    }

    # The brief walker, asserted directly. expected.json stores {severity, path} only and the
    # comparison above selects those two columns, so the line count and the ticked-only filter —
    # everything the walker actually decides — live in `detail` and are compared by nothing.
    let want_brief = [{id: "STALE-2", lines: 3}]
    let got_brief = (leftover-briefs (read-text ($run | path join "docs" "workstreams" "stale.md") | lines))
    if $got_brief == $want_brief {
        print $"(ansi green)ok(ansi reset)   brief walker — ($want_brief | to nuon)"
    } else {
        print $"(ansi red)FAIL(ansi reset) brief walker"
        print $"       want: ($want_brief | to nuon)"
        print $"       got:  ($got_brief | to nuon)"
    }

    rm -rf $tmp
    if (($results | all {|r| $r.status != "FAIL"}) and $derived and ($noise | is-empty) and ($got_brief == $want_brief)) {
        print $"\n(ansi green)selftest passed(ansi reset)"
    } else {
        print $"\n(ansi red)selftest failed(ansi reset)"
        exit 1
    }
}

# A throwaway repo whose `other` branch allocates CROSS-1 to different work — the collision that only
# surfaces at merge, and the reason the check reads across refs rather than the working tree.
def seed-repo [dir: path] {
    git-in $dir [init -b main]
    git-in $dir [add -A]
    git-in $dir [commit -m fixture]
    git-in $dir [checkout -q -b other]
    let f = ($dir | path join "docs" "workstreams" "crossover.md")
    (read-text $f | str replace "**CROSS-1** — one session" "**CROSS-1** — something else entirely") | save -f $f
    git-in $dir [commit -am diverge]
    git-in $dir [checkout -q main]
}

def git-in [dir: path, args: list<string>] {
    let r = (^git -C $dir -c user.name=selftest -c user.email=selftest@local -c commit.gpgsign=false ...$args | complete)
    if $r.exit_code != 0 { error make {msg: $"git ($args | str join ' ') failed: ($r.stderr | str trim)"} }
}

# ---------------------------------------------------------------------- hub

# Dispatch only, and every screen reaches a subcommand that already works from the command line —
# so new features land as subcommands first and the hub is only how you find them.
def hub [path: string] {
    let docs = (require-docs $path)
    loop {
        let trackers = (main status --path $docs)
        # `input list` on an empty list raises a type mismatch rather than a friendly error, so
        # both data-driven lists are guarded. The menu below always carries the action rows.
        if ($trackers | is-empty) {
            print $"(ansi yellow)no trackers in ($docs)(ansi reset)"
            return
        }
        # Sentinels take the status record's own columns, so a column added to `status` later
        # propagates here instead of rendering the table ragged.
        let blank = ($trackers | first | columns | reduce --fold {} {|c, acc| $acc | insert $c ""})
        let menu = (["· audit" "· snags" "· more…" "· quit"] | each {|l| $blank | update tracker $l})
        let sel = ($trackers | append $menu | input list)
        if $sel == null { return }
        match $sel.tracker {
            "· quit" => { return }
            "· audit" => { hub-page { main audit --path $docs } }
            "· snags" => { hub-page { main snags --path $docs } }
            "· more…" => { hub-more $docs }
            _ => { if (hub-start $docs $sel.tracker) { return } }
        }
    }
}

# Show a subcommand's output and hold it there — the next `input list` would otherwise redraw
# straight over the thing you asked to see.
def hub-page [body: closure] {
    try { print (do $body) } catch {|e| print $"(ansi red)($e.msg)(ansi reset)" }
    input "enter to continue " | ignore
}

# True when a prompt was generated: the hub exits on that, so the terminal is yours to paste into.
def hub-start [docs: path, tracker: string]: nothing -> bool {
    let open = (main sessions $tracker --path $docs --open)
    if ($open | is-empty) {
        print $"(ansi yellow)($tracker): every session ticked — nothing to start(ansi reset)"
        return false
    }
    let sel = ($open | select id title brief_lines is_next | input list)
    if $sel == null { return false }
    let prompt = (main start $tracker $sel.id --path $docs)
    print $prompt
    if (["copy to clipboard" "done"] | input list) == "copy to clipboard" { to-clipboard $prompt }
    true
}

def hub-more [docs: path] {
    let sel = (["status --write" "new tracker" "selftest" "back"] | input list)
    match $sel {
        "status --write" => { hub-page { main status --path $docs --write } }
        "new tracker" => {
            let name = (input "tracker name: " | str trim)
            if ($name | is-not-empty) { hub-page { main new $name --path $docs } }
        }
        "selftest" => { hub-page { main selftest } }
        _ => {}
    }
}

# Loud on a miss: wl-clipboard ships only with the sway/niri desktop modules, so a host can
# legitimately have neither tool, and a silent no-op there reads exactly like a successful copy.
def to-clipboard [text: string] {
    let tool = (if $nu.os-info.name == "macos" { "pbcopy" } else { "wl-copy" })
    if (which $tool | is-empty) {
        print $"(ansi yellow)note(ansi reset) ($tool) not on PATH — nothing copied"
        return
    }
    $text | ^$tool
    print $"(ansi green)copied(ansi reset) ($text | into binary | length) bytes"
}

# --------------------------------------------------------------------- entry

# The header comment block above is the help text — one home for the command list.
def help-text []: nothing -> string {
    read-text $env.CURRENT_FILE | lines | skip 1 | take while {|l| $l | str starts-with "#"}
        | each {|l| $l | str substring 1.. | str trim --right} | str join "\n"
}

def "main help" [] { print (help-text) }

# Is a person driving this? Measured, because getting it wrong hands an agent a TUI.
#
# `is-terminal --stdout` is useless here: nushell replaces stdout in script mode, so it reports
# false even when the process owns a real pty — verified under `pty.fork`, where stdin and stderr
# both report true on the same fd. Stdin is the only half the script can see for itself. The
# wrapper on PATH is a shell, where `[ -t 1 ]` does work, and it passes its answer down; absent
# the wrapper (`nu docs.nu` direct) stdin decides alone. Do not fold these back into one check.
def tty-driven []: nothing -> bool {
    (is-terminal --stdin) and (($env | get -o DOCKET_STDOUT | default "1") == "1")
}

# Interactive only. Piped or redirected — which is every agent and every script — this keeps the
# old behaviour exactly: print the help and exit.
def main [--path: string = "docs"] {
    if (tty-driven) { hub $path } else { print (help-text) }
}
