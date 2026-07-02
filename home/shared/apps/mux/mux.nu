# mux — herdr hub launcher (worktree-aware)
#
# One always-on `hub` session you curate: `pin` a project to add all its git worktrees as
# workspaces (labelled `<project>/<worktree>`), `unpin` to remove them. A project is a
# ~/projects/<name> dir containing `.bare`; each worktree is a herdr workspace. One hub ⇒ one
# agent sidebar across every project you're actively working on (see docs/multiplexing.md).
#
#   mux                    attach (or create) the hub
#   mux <project>          pin <project> if absent, focus its main, then attach the hub
#   mux pin <project>      add a hub workspace per worktree of <project> (idempotent)
#   mux unpin <project>    close the hub's <project>/* workspaces (view-only — git untouched)
#   mux --project [name]   dedicated per-project session, all worktrees (cwd if no name)
#   mux reset | --reset    delete the hub then recreate it (run from OUTSIDE herdr)
#   mux --project --reset  same, for the resolved project session
#   mux worktree open <name>   open (or focus) a worktree as a workspace (run inside herdr)
#   mux worktree add <name>    delegate to `glitter worktree add`, then open it (inside herdr)
#   mux worktree all           open every worktree of the current project (inside herdr)
#
# pin/unpin and `mux <project>` are HUB-SCOPED: they target the hub's socket directly (via
# herdr-ctl), so they behave identically from inside the hub, another session, or outside herdr —
# the hub must already be running (`mux` creates it). Worktree enumeration comes from
# `glittering worktree list --cached` (raw `git worktree list` fallback).
#
# Override: $env.MUX_SESSION sets the per-project session name explicitly.
#
# Only `const`/`def` at top level — so `nu -c 'source mux.nu'` parse-checks without running.

# The always-on hub session `mux` attaches by default and curates via pin/unpin. Named `hub`
# (not `default`) so it's cleanly resettable and leaves herdr's `default` as scratch.
const HUB = "hub"

# session names must be [A-Za-z0-9_-]; collapse runs and strip edge dashes
def sanitize []: string -> string {
    $in
    | str replace --all --regex '[^A-Za-z0-9_-]' '-'
    | str replace --all --regex '-+' '-'
    | str trim --char '-'
}

# --- resolution (backend-neutral, glittering-backed) ------------------------

# Walk up from `dir` to the first ancestor containing `.bare`, bounded to ~/projects/*.
# Structural + submodule-safe (never calls `git rev-parse`). Returns abs path or null.
def project-root [dir: string] {
    let base = ([$env.HOME "projects"] | path join)
    mut d = ($dir | path expand)
    loop {
        if (([$d ".bare"] | path join) | path exists) { return $d }
        let parent = ($d | path dirname)
        if ($d == $base) or ($parent == $d) or (not ($d | str starts-with $base)) { break }
        $d = $parent
    }
    null
}

# Authoritative worktrees for a project root. glittering when present; raw-git fallback.
# Rows: glittering's full record, or fallback {name, path, branch}.
def worktrees [root: string] {
    if (which glittering | is-not-empty) {
        let r = (do -i { ^glittering worktree list --cached --path $root | complete })
        if ($r != null) and ($r.exit_code == 0) and (($r.stdout | str trim) | is-not-empty) {
            return ($r.stdout | from json | get worktrees)
        }
    }
    # fallback: parse `git worktree list --porcelain`, drop the bare entry
    let gitdir = ([$root ".bare"] | path join)
    let r = (do -i { ^git --git-dir $gitdir worktree list --porcelain | complete })
    if ($r == null) or ($r.exit_code != 0) { return [] }
    $r.stdout
    | split row "\n\n"
    | each {|blk|
        let lines = ($blk | lines)
        let wline = ($lines | where {|l| $l | str starts-with "worktree " })
        if ($wline | is-empty) or ($lines | any {|l| $l == "bare" }) {
            null
        } else {
            let wpath = ($wline | first | str replace "worktree " "")
            let brl = ($lines | where {|l| $l | str starts-with "branch " })
            let branch = (if ($brl | is-empty) { "" } else { $brl | first | str replace "branch refs/heads/" "" })
            { name: ($wpath | path basename), path: ($wpath | path expand), branch: $branch }
        }
    }
    | compact
}

# Longest path-prefix match of pwd against worktree paths (handles nested submodule cwd).
def current-worktree [pwd: string, wts: list<any>] {
    let p = ($pwd | path expand)
    let matches = ($wts
        | where {|w| ($p == $w.path) or ($p | str starts-with ($w.path + "/")) }
        | sort-by {|w| $w.path | str length })
    if ($matches | is-empty) { null } else { $matches | last }
}

# { kind, project, root, worktree, worktrees, session_override } resolved from cwd.
def resolve [] {
    let pwd = ($env.PWD | path expand)
    let root = (project-root $pwd)
    let override = ($env.MUX_SESSION? | default null)
    if ($root == null) {
        return {
            kind: "other",
            project: ($pwd | path basename | sanitize),
            root: $pwd,
            worktree: null,
            worktrees: [],
            session_override: $override,
        }
    }
    let wts = (worktrees $root)
    let cur = (current-worktree $pwd $wts)
    {
        kind: (if ($cur != null) { "worktree" } else { "project" }),
        project: ($root | path basename | sanitize),
        root: $root,
        worktree: $cur,
        worktrees: $wts,
        session_override: $override,
    }
}

# Session name for a resolved record ($env.MUX_SESSION wins; else the project name).
def target-session [r: record] {
    ($r.session_override | default $r.project) | sanitize
}

# Resolve a project BY NAME (~/projects/<name>) to a `resolve`-shaped record, or null if it has no
# `.bare`. Raw name for the path; sanitized for labels/session. Used by pin, the `mux <project>`
# sugar, and `mux --project <name>`.
def project-by-name [name: string] {
    let root = ([$env.HOME "projects" $name] | path join)
    if not (([$root ".bare"] | path join) | path exists) { return null }
    {
        kind: "project",
        project: ($name | sanitize),
        root: $root,
        worktree: null,
        worktrees: (worktrees $root),
        session_override: ($env.MUX_SESSION? | default null),
    }
}

# --- herdr backend (Tier 0: create/attach only — no socket build) -----------

# Socket path for an existing named session, or null. Source of truth for scoping.
def session-socket [name: string] {
    let r = (do -i { ^herdr session list --json | complete })
    if ($r == null) or ($r.exit_code != 0) { return null }
    let m = ($r.stdout | from json | get sessions | where name == $name)
    if ($m | is-empty) { null } else { $m | first | get socket_path }
}

# Is a named session listed at all (running or stopped/resurrectable)?
def herdr-session-exists [name: string] {
    let r = (do -i { ^herdr session list --json | complete })
    if ($r == null) or ($r.exit_code != 0) { return false }
    $name in ($r.stdout | from json | get sessions | each {|s| $s.name })
}

# Is a named session's server currently running (socket live)?
def herdr-running [name: string] {
    let r = (do -i { ^herdr session list --json | complete })
    if ($r == null) or ($r.exit_code != 0) { return false }
    let m = ($r.stdout | from json | get sessions | where name == $name)
    if ($m | is-empty) { false } else { $m | first | get running }
}

# Run a herdr socket command scoped to an EXISTING session (pins HERDR_SOCKET_PATH).
# Returns the `complete` record, or null if the session/socket is absent.
def herdr-ctl [session: string, args: list<string>] {
    let sock = (session-socket $session)
    if ($sock == null) { return null }
    with-env { HERDR_SOCKET_PATH: $sock } { do -i { ^herdr ...$args | complete } }
}

# Guard for hub-scoped ops: the hub must be running (socket builds need a live server — a session
# can't be populated before its first blocking attach). `mux` creates it.
def require-hub [] {
    if (which herdr | is-empty) {
        error make { msg: "mux: herdr not found on PATH." }
    }
    if not (herdr-running $HUB) {
        error make { msg: $"mux: the hub is not running — run `mux` once to create it, then retry." }
    }
}

# Full teardown of a session: stop (a running session can't be deleted) then delete. Idempotent.
def teardown-session [session: string] {
    if (herdr-session-exists $session) {
        do -i { ^herdr session stop $session }
        do -i { ^herdr session delete $session }
    }
}

# Pre-authorize <path>/.envrc (if present + direnv installed) so a just-CREATED worktree's devshell
# loads without a manual `direnv allow`. Only called for worktrees mux itself creates (`worktree add`).
def direnv-allow [path: string] {
    if (which direnv | is-empty) { return }
    let rc = ([$path ".envrc"] | path join)
    if ($rc | path exists) { do -i { ^direnv allow $rc } }
}

# Landing dir for a resolved record (worktree path; else prefer `main`; else root).
def landing-dir [r: record] {
    if ($r.worktree != null) {
        $r.worktree.path
    } else if (($r.worktrees | length) > 0) {
        let main = ($r.worktrees | where name == "main")
        if ($main | is-not-empty) { $main | first | get path } else { $r.worktrees | first | get path }
    } else {
        $r.root
    }
}

# Worktree NAME mux would land on (cwd's worktree; else `main`; else first; else null when there
# are no worktrees). Mirrors `landing-dir`'s preference so the initial label and landing agree.
def landing-worktree-name [r: record] {
    if ($r.worktree != null) {
        $r.worktree.name
    } else if (($r.worktrees | length) > 0) {
        let main = ($r.worktrees | where name == "main")
        if ($main | is-not-empty) { "main" } else { $r.worktrees | first | get name }
    } else {
        null
    }
}

# Background: once <session> comes up with a single (fresh) workspace, rename it to <label> so the
# sidebar shows `<project>/<worktree>`. Create-path only; runs during the blocking attach, then
# exits. Silent (socket calls only). Skips multi-workspace sessions so labels aren't clobbered.
def label-workspace-bg [session: string, label: string] {
    job spawn {
        mut tries = 0
        loop {
            $tries = $tries + 1
            if $tries >= 50 { return }
            sleep 100ms
            if not (herdr-running $session) { continue }
            let r = (herdr-ctl $session ["workspace" "list"])
            if ($r == null) or ($r.exit_code != 0) { continue }
            let wss = ($r.stdout | from json | get result.workspaces)
            if ($wss | is-empty) { continue }
            if (($wss | length) != 1) { return }        # multi-workspace → leave labels alone
            let rr = (herdr-ctl $session ["workspace" "rename" ($wss | first | get workspace_id) $label])
            if ($rr != null) and ($rr.exit_code == 0) { return }
        }
    }
}

# Create-or-attach the per-project session, landing at the right dir. BLOCKING (TUI handover).
def launch-herdr [r: record] {
    let session = (target-session $r)
    if (herdr-running $session) {
        ^herdr session attach $session
    } else {
        let land = (landing-worktree-name $r)
        let label = (if ($land == null) { $session } else { $"($r.project)/($land)" })
        cd (landing-dir $r)
        label-workspace-bg $session $label
        ^herdr --session $session
    }
}

# --- hub (curated cross-project session: pin/unpin projects as worktree workspaces) ---------

# All pinnable projects: ~/projects/*/ containing `.bare`. Used for "available projects" hints.
def all-projects [] {
    let base = ([$env.HOME "projects"] | path join)
    if not ($base | path exists) { return [] }
    ls $base | where type == dir | get name
    | where {|d| ([$d ".bare"] | path join) | path exists }
    | each {|d| { project: ($d | path basename | sanitize), root: $d } }
    | sort-by project
}

# Labels of the workspaces currently in <session> (idempotent dedupe), or [] if absent.
def session-workspaces [session: string] {
    let r = (herdr-ctl $session ["workspace" "list"])
    if ($r == null) or ($r.exit_code != 0) { return [] }
    $r.stdout | from json | get result.workspaces | each {|w| $w.label }
}

# Full workspace records at a socket (need workspace_id/number for sort/unpin/focus), [] on failure.
def workspaces-at [sock: string] {
    if ($sock | is-empty) { return [] }
    let r = (with-env { HERDR_SOCKET_PATH: $sock } { do -i { ^herdr workspace list | complete } })
    if ($r == null) or ($r.exit_code != 0) { return [] }
    $r.stdout | from json | get result.workspaces
}

# Socket of the session mux is currently inside (from the pane env), or null.
def current-socket [] { $env.HERDR_SOCKET_PATH? | default null }

def hub-workspaces [] { workspaces-at (session-socket $HUB) }

# Attach (or create) the hub. BLOCKING when it hands over to the TUI. Inside herdr, just hint.
def open-hub [] {
    if ($env.HERDR_ENV? == "1") {
        print $"In herdr. Press cmd+alt+space \(goto\) and pick '($HUB)'."
        return
    }
    if (herdr-running $HUB) {
        ^herdr session attach $HUB
    } else {
        # Fresh hub: land its lone default workspace in ~ (a neutral scratch shell, labelled `~`),
        # independent of wherever `mux` was launched from.
        cd $env.HOME
        label-workspace-bg $HUB "~"
        ^herdr --session $HUB
    }
}

# Add a hub workspace per worktree of <rec>, labelled `<project>/<worktree>`. Idempotent (dedupe by
# label against the hub). Hub-scoped via herdr-ctl. Returns the number added.
def pin-project [rec: record] {
    if ($rec.worktrees | is-empty) {
        error make { msg: $"mux pin: '($rec.project)' has no worktrees — create one with: glitter worktree add main" }
    }
    let existing = (session-workspaces $HUB)
    mut added = 0
    for wt in $rec.worktrees {
        let label = $"($rec.project)/($wt.name)"
        if ($label in $existing) { continue }
        herdr-ctl $HUB ["workspace" "create" "--cwd" $wt.path "--label" $label "--no-focus"]
        $added = $added + 1
    }
    $added
}

# Focus the hub workspace for <project>: prefer `<project>/main`, else the lowest-numbered. No-op
# if none are pinned. Hub-scoped.
def focus-first [project: string] {
    let mine = (hub-workspaces | where {|w| $w.label | str starts-with $"($project)/" })
    if ($mine | is-empty) { return }
    let main = ($mine | where label == $"($project)/main")
    let pick = (if ($main | is-not-empty) { $main | first } else { $mine | sort-by number | first })
    herdr-ctl $HUB ["workspace" "focus" $pick.workspace_id]
}

# Reorder the spaces at <sock> alphabetically by label (the `~` scratch shell kept first) via the
# socket `workspace.move` method — herdr's CLI can't reorder. Best-effort: silent no-op if `nc` or
# the socket is unavailable, or a move fails (never disrupts the layout). herdr serves one request
# per connection, so this issues one short-lived `nc` call per moved workspace (~ms each). The
# working list mirrors herdr's post-removal insert semantics, so only out-of-place spaces move.
def sort-workspaces [sock: string] {
    if (which nc | is-empty) { return }
    if ($sock | is-empty) { return }
    let wss = (workspaces-at $sock)
    if (($wss | length) < 2) { return }
    let desired = ($wss
        | insert _k {|w| if ($w.label == "~") { "" } else { $w.label }}
        | sort-by _k
        | get workspace_id)
    mut working = ($wss | sort-by number | get workspace_id)
    for i in 0..(($desired | length) - 1) {
        let want = ($desired | get $i)
        if (($working | get $i) == $want) { continue }
        let from = ($working | enumerate | where item == $want | get 0.index)
        $working = ($working | drop nth $from | insert $i $want)
        let body = ({ id: "mux-sort", method: "workspace.move", params: { workspace_id: $want, insert_index: $i } } | to json --raw)
        do -i { ($body + "\n") | ^nc -U -w 2 $sock | ignore }
    }
}

# Sort the hub's spaces (used after pin). Hub-scoped.
def sort-hub [] { sort-workspaces (session-socket $HUB) }

# Tear down the hub and recreate it fresh (a single `~` shell). Run from OUTSIDE herdr (resetting
# the attached session would kill this pane).
def reset-hub [] {
    if ($env.HERDR_ENV? == "1") {
        error make { msg: "mux reset: run from outside herdr — resetting the hub would kill this pane." }
    }
    teardown-session $HUB
    open-hub
}

# Tear down a per-project session and relaunch it. Run from OUTSIDE herdr.
def reset-project [rec: record] {
    if ($env.HERDR_ENV? == "1") {
        error make { msg: "mux --project --reset: run from outside herdr — deleting the attached session would kill this pane." }
    }
    teardown-session (target-session $rec)
    launch-herdr $rec
}

# --- worktree ops (open worktrees as workspaces in the CURRENT running session) -------------

# Guard/context for `mux worktree *`: require herdr + being inside a session + a project.
def worktree-ctx [] {
    if (which herdr | is-empty) {
        error make { msg: "mux worktree: herdr not found on PATH." }
    }
    if ($env.HERDR_ENV? != "1") {
        error make { msg: "mux worktree: run inside herdr — it opens in the current session." }
    }
    let r = (resolve)
    if ($r.kind == "other") {
        error make { msg: "mux worktree: not inside a ~/projects/* project." }
    }
    $r
}

# Open <path> as a workspace labelled <label> in the current session (HERDR_SOCKET_PATH inherited
# from the pane), or focus it if a workspace with that label already exists. The `.bare` layout
# can't use `herdr worktree open` (linked_worktree_source), so this uses plain `workspace create`.
def open-worktree-ws [path: string, label: string, --focus] {
    let cur = (do -i { ^herdr workspace list | complete })
    let open = (if ($cur != null) and ($cur.exit_code == 0) {
        $cur.stdout | from json | get result.workspaces | where label == $label | get 0?
    } else { null })
    if ($open != null) {
        if $focus { ^herdr workspace focus $open.workspace_id }
    } else {
        let foc = (if $focus { "--focus" } else { "--no-focus" })
        ^herdr workspace create --cwd $path --label $label $foc
    }
}

# --- entry points -----------------------------------------------------------

def main [name?: string, --project, --reset] {
    if (which herdr | is-empty) {
        error make { msg: "mux: herdr not found on PATH — mux requires herdr." }
    }
    if $project {
        # dedicated per-project session, all worktrees (cwd if no name)
        let rec = (if ($name != null) { project-by-name $name } else { resolve })
        if ($rec == null) {
            error make { msg: $"mux --project: no project '($name)' in ~/projects." }
        }
        if $reset { reset-project $rec } else { launch-herdr $rec }
        return
    }
    # hub mode
    if $reset { reset-hub; return }
    if ($name != null) {
        require-hub
        let rec = (project-by-name $name)
        if ($rec == null) {
            error make { msg: $"mux: no project '($name)' in ~/projects. Available: (all-projects | get project | str join ', ')" }
        }
        pin-project $rec
        sort-hub
        focus-first $rec.project
        if ($env.HERDR_ENV? == "1") {
            print $"pinned & focused '($rec.project)'. cmd+alt+space \(goto\) → '($HUB)'."
        } else {
            ^herdr session attach $HUB
        }
        return
    }
    open-hub
}

# Add <project>'s worktrees to the hub as workspaces (idempotent). Hub-scoped: works from anywhere
# (inside the hub, another session, or outside herdr) as long as the hub is running.
def "main pin" [project: string] {
    require-hub
    let rec = (project-by-name $project)
    if ($rec == null) {
        error make { msg: $"mux pin: no project '($project)' in ~/projects. Available: (all-projects | get project | str join ', ')" }
    }
    let n = (pin-project $rec)
    sort-hub
    print $"pin: added ($n) workspace\(s\) for '($rec.project)' to the hub."
}

# Close the hub's <project>/* workspaces. VIEW-ONLY — never removes git worktrees. Hub-scoped.
def "main unpin" [project: string] {
    require-hub
    let prefix = $"(($project | sanitize))/"
    let mine = (hub-workspaces | where {|w| $w.label | str starts-with $prefix })
    if ($mine | is-empty) {
        print $"unpin: nothing pinned for '($project)'."
        return
    }
    for w in $mine {
        herdr-ctl $HUB ["workspace" "close" $w.workspace_id]
    }
    print $"unpin: closed ($mine | length) workspace\(s\) for '($project)' \(view-only — git worktrees untouched\)."
}

# Reorder spaces alphabetically. Inside herdr: sorts the current session (hub OR project session).
# Outside herdr: sorts the hub. (mux already auto-sorts after pin and worktree ops — this is manual.)
def "main sort" [] {
    if (which herdr | is-empty) { error make { msg: "mux sort: herdr not found on PATH." } }
    let sock = (if ($env.HERDR_ENV? == "1") { current-socket } else { session-socket $HUB })
    if ($sock == null) {
        error make { msg: "mux sort: no live session — run inside herdr (sorts the current session), or with the hub running (sorts the hub)." }
    }
    sort-workspaces $sock
    print "sorted spaces alphabetically."
}

# Reset the hub (alias for `mux --reset`). `--force` accepted for compatibility (unused).
def "main reset" [--force] {
    if (which herdr | is-empty) {
        error make { msg: "mux reset: herdr not found on PATH." }
    }
    reset-hub
}

# Removed: the hub is the default now. Stub kept to redirect muscle memory.
def "main dash" [] {
    print "mux dash was removed — the hub is the default now: `mux` attaches it, `mux pin <project>` adds a project (per-worktree), `mux unpin <project>` removes it."
}

def "main worktree" [] {
    print "mux worktree: open <name> | add <name> [glitter flags] | all"
}

# Open (or focus) an existing worktree as a workspace in the current session.
def "main worktree open" [name: string] {
    let r = (worktree-ctx)
    let wt = ($r.worktrees | where name == $name | get 0?)
    if ($wt == null) {
        error make { msg: $"mux worktree: no '($name)' in '($r.project)' — create it with: glitter worktree add ($name)" }
    }
    open-worktree-ws $wt.path $"($r.project)/($name)" --focus
    sort-workspaces (current-socket)
}

# Delegate creation to glittering (owns lifecycle; extra flags pass through), then open it.
def "main worktree add" [name: string, ...rest: string] {
    let r = (worktree-ctx)
    let res = (do -i { ^glittering worktree add --path $r.root ...$rest $name | complete })
    if ($res == null) {
        error make { msg: "mux worktree add: could not run glittering." }
    }
    if ($res.exit_code not-in [0 3]) {
        error make { msg: $"mux worktree add: glittering failed \(exit ($res.exit_code)\): ($res.stderr)" }
    }
    let out = ($res.stdout | from json)
    if ($res.exit_code == 3) {
        print $"⚠ created '($out.name)' \(degraded\): ($out.warnings? | default [] | str join '; ')"
    } else {
        print $"created worktree '($out.name)'"
    }
    direnv-allow $out.path        # trust the .envrc only for a worktree we just created
    open-worktree-ws $out.path $"($r.project)/($out.name)" --focus
    sort-workspaces (current-socket)
}

# Open every worktree of the current project as a workspace (dedupe by label).
def "main worktree all" [] {
    let r = (worktree-ctx)
    for wt in $r.worktrees {
        open-worktree-ws $wt.path $"($r.project)/($wt.name)"
    }
    sort-workspaces (current-socket)
    print $"($r.worktrees | length) worktree\(s\) open in '($r.project)'."
}
