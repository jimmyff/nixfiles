# mux — herdr workspace launcher (worktree-aware)
#
# Resolves a herdr session + landing dir from the current directory, then attaches to (or
# creates) the matching herdr session. A project (a ~/projects/<name> dir containing `.bare`)
# maps to a herdr session; each git worktree is a herdr workspace — herdr manages the
# worktree↔workspace binding natively (see docs/multiplexing.md).
#
#   mux         launch/attach the herdr session for the current directory
#   mux reset [--force]   delete the resolved session then relaunch (run from OUTSIDE herdr)
#   mux dash [--dry-run]  ensure the always-running `default` session has one terminal per
#               project root, then attach to it (a cross-project hub)
#   mux worktree open <name>   open (or focus) a worktree as a workspace here (run inside herdr)
#   mux worktree add <name>    delegate to `glitter worktree add`, then open it (run inside herdr)
#   mux worktree all           open every worktree of the current project (run inside herdr)
#
# Worktree enumeration comes from `glittering worktree list --cached` (raw `git worktree list`
# fallback). herdr can't populate a session before its (blocking) attach, so `mux` lands herdr's
# default pane — run `glitter overview` for worktree status. Only an already-running session
# accepts socket builds, so `mux dash` populates the always-on `default` session.
#
# Override: $env.MUX_SESSION sets the session name explicitly.
#
# Only `const`/`def` at top level — so `nu -c 'source mux.nu'` parse-checks without running.

# Always-on `mux dash` folders beyond ~/projects/*/.bare (expanded; skipped if absent).
const DASH_EXTRA = ["~/nixfiles"]

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

# Background: once <session> comes up with a single (fresh) workspace, label it <session> so the
# sidebar shows the project. Create-path only; runs during the blocking attach, then exits. Silent
# (socket calls only). Skips multi-workspace sessions so per-worktree labels aren't clobbered.
def label-workspace-bg [session: string] {
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
            if (($wss | length) != 1) { return }        # multi-worktree → leave labels alone
            let rr = (herdr-ctl $session ["workspace" "rename" ($wss | first | get workspace_id) $session])
            if ($rr != null) and ($rr.exit_code == 0) { return }
        }
    }
}

# Create-or-attach the session, landing at the right dir. BLOCKING (TUI handover).
def launch-herdr [r: record] {
    let session = (target-session $r)
    if (herdr-running $session) {
        ^herdr session attach $session
    } else {
        cd (landing-dir $r)
        label-workspace-bg $session
        ^herdr --session $session
    }
}

# --- dash (cross-project hub: one terminal per project root) ----------------

# All dash entries: ~/projects/*/ containing `.bare`, plus existing DASH_EXTRA folders.
def all-projects [] {
    let base = ([$env.HOME "projects"] | path join)
    let projects = (if ($base | path exists) {
        ls $base | where type == dir | get name
        | where {|d| ([$d ".bare"] | path join) | path exists }
        | each {|d| { project: ($d | path basename | sanitize), root: $d } }
        | sort-by project
    } else { [] })
    let extra = ($DASH_EXTRA
        | each {|p| $p | path expand }
        | where {|d| $d | path exists }
        | each {|d| { project: ($d | path basename | sanitize), root: $d } })
    $projects | append $extra
}

# Labels of the workspaces currently in <session> (idempotent dedupe), or [] if absent.
def session-workspaces [session: string] {
    let r = (herdr-ctl $session ["workspace" "list"])
    if ($r == null) or ($r.exit_code != 0) { return [] }
    $r.stdout | from json | get result.workspaces | each {|w| $w.label }
}

# Cross-project hub. herdr can't build a session before attaching, so the hub lives in the
# always-running `default` session: ensure a workspace (a terminal at the project root) for every
# project, then attach. Idempotent — only missing projects are added (dedupe by label).
def open-dash [--dry-run] {
    if (which herdr | is-empty) {
        error make { msg: "mux dash: herdr not found on PATH." }
    }
    let running = (herdr-running "default")
    let existing = (if $running { session-workspaces "default" } else { [] })
    let missing = (all-projects | where {|p| $p.project not-in $existing })
    if $dry_run {
        print { hub: "default", running: $running, existing: $existing, would_add: ($missing | get project) }
        return
    }
    if not $running {
        # Can't socket-build before the (blocking) attach, so just start `default`; the next
        # `mux dash` (with the server up) populates it.
        print "mux dash: 'default' not running — starting it; re-run `mux dash` to add projects."
        ^herdr
        return
    }
    for p in $missing {
        herdr-ctl "default" ["workspace" "create" "--cwd" $p.root "--label" $p.project "--no-focus"]
    }
    if ($env.HERDR_ENV? == "1") {
        print $"dash: added ($missing | length) workspace\(s\) to 'default'. cmd+alt+space \(goto\) → default."
    } else {
        ^herdr session attach "default"
    }
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

def main [] {
    if (which herdr | is-empty) {
        error make { msg: "mux: herdr not found on PATH — mux requires herdr." }
    }
    let r = (resolve)
    let session = (target-session $r)
    if ($env.HERDR_ENV? == "1") {
        print $"In herdr. Press cmd+alt+space \(goto\) and pick '($session)' — or run mux from outside herdr to attach."
    } else {
        launch-herdr $r
    }
}

def "main reset" [--force] {
    if (which herdr | is-empty) {
        error make { msg: "mux reset: herdr not found on PATH." }
    }
    if ($env.HERDR_ENV? == "1") {
        error make { msg: "mux reset: run from outside herdr — deleting the attached session would kill this pane." }
    }
    let r = (resolve)
    let session = (target-session $r)
    # Full teardown: a running session can't be deleted, so stop first, then delete.
    if (herdr-session-exists $session) {
        do -i { ^herdr session stop $session }
        do -i { ^herdr session delete $session }
    }
    launch-herdr $r
}

def "main dash" [--dry-run] { open-dash --dry-run=$dry_run }

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
    open-worktree-ws $wt.path $name --focus
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
    open-worktree-ws $out.path $out.name --focus
}

# Open every worktree of the current project as a workspace (dedupe by label).
def "main worktree all" [] {
    let r = (worktree-ctx)
    for wt in $r.worktrees {
        open-worktree-ws $wt.path $wt.name
    }
    print $"($r.worktrees | length) worktree\(s\) open in '($r.project)'."
}
