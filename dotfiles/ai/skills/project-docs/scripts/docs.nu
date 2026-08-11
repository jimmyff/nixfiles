#!/usr/bin/env nu
# docs.nu — helper for the project-docs skill.
#
#   status  [--path <docs>] [--write]   per-tracker state; --write regenerates the README table
#   new     <name> [--path <docs>]      scaffold a tracker from templates/workstream.md
#   audit   [--path <docs>]             advisory checks; never edits anything
#   snags   [--path <docs>]             per-tracker snag list, with age derived from git blame
#   fixture --write [--path <dir>]      write a sample tree from templates/ (gitignored, for reading)
#   selftest                            build a throwaway tree, assert every check against expected.json
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

# YAML frontmatter, or {} when absent or unparseable. One parser for all four kinds.
def frontmatter [ls: list<string>]: nothing -> record {
    if ($ls | is-empty) or (($ls | first | str trim) != "---") { return {} }
    let close = ($ls | skip 1 | enumerate | where {|r| ($r.item | str trim) == "---"} | get -o 0.index)
    if ($close == null) or ($close == 0) { return {} }
    let parsed = (try { $ls | slice 1..$close | str join "\n" | from yaml } catch { null })
    if ($parsed | describe | str starts-with "record") { $parsed } else { {} }
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

# Ticked `## Sessions` rows still carrying indented prose. A brief dies when its row ticks, so
# anything left under one has outlived its session — the one staleness check a brief affords,
# because the tick is a mechanical clearing event. Unticked briefs are deliberately unchecked (the
# snags reasoning: thresholds manufacture false positives), and `## Log` rows are exempt — a settled
# log entry legitimately carries a prose line. Blank lines don't end a row's scope (a brief may
# hold paragraphs); any other column-0 line does.
def leftover-briefs [ls: list<string>]: nothing -> table {
    let r = (section-range $ls "Sessions")
    if $r == null { return [] }
    let acc = ($ls | slice $r.start..<$r.end | reduce --fold {out: [], id: null, n: 0} {|l, acc|
        let row = ($l | parse --regex $ROW_RE)
        if ($row | is-not-empty) {
            let it = ($row | first)
            (flush-brief $acc) | update id (if ($it.state | str lowercase) == "x" { $it.id } else { null })
        } else if ($l =~ r#'^\s+\S'#) {
            if $acc.id == null { $acc } else { $acc | update n ($acc.n + 1) }
        } else if (($l | str trim) | is-empty) {
            $acc
        } else {
            flush-brief $acc
        }
    })
    (flush-brief $acc).out
}

def flush-brief [acc: record]: nothing -> record {
    if $acc.id != null and $acc.n > 0 {
        {out: ($acc.out | append {id: $acc.id, lines: $acc.n}), id: null, n: 0}
    } else {
        {out: $acc.out, id: null, n: 0}
    }
}

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

def require-docs [path: string]: nothing -> path {
    let docs = ($path | path expand)
    if not ($docs | path exists) { error make {msg: $"no such directory: ($docs)"} }
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

def "main new" [name: string, --path: string = "docs", --prefix: string = "", --design: string = ""] {
    let dir = (($path | path expand) | path join "workstreams")
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

    rm -rf $tmp
    if (($results | all {|r| $r.status != "FAIL"}) and $derived and ($noise | is-empty)) {
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

def main [] {
    read-text $env.CURRENT_FILE | lines | skip 1 | take while {|l| $l | str starts-with "#"}
        | each {|l| $l | str substring 1.. | str trim --right} | str join "\n" | print $in
}
