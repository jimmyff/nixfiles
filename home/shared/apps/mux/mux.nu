# mux — zellij workspace launcher (sessions = workspaces)
#
# Resolves a session name + root dir + private layout from the current directory,
# then attaches to (or creates) the matching zellij session.
#
#   mux         launch/attach the workspace for the current directory
#   mux reset   delete the resolved session then relaunch (escape a bad resurrection)
#   mux init    scaffold a tabs-only .zellij.kdl layout in the current directory
#
# Bar chrome is the single source of truth: project .zellij.kdl files hold only
# tabs/panes, and mux injects the default_tab_template from jimmyff.kdl at launch
# (see merge-layout). Editing jimmyff.kdl thus reaches every new session — no
# re-scaffolding. See dotfiles/zellij/layouts/jimmyff.kdl and docs/multiplexing.md.
#
# Overrides: $env.ZJ_SESSION (session name), $env.ZJ_LAYOUT (layout name or path).
#
# Only `const`/`def` at top level — so `nu -c 'source mux.nu'` parse-checks without running.

# Canonical layout supplying the default_tab_template injected at launch (mkOutOfStoreSymlink
# target of ~/.config/zellij/layouts). See merge-layout.
const DEFAULT_LAYOUT = '~/.config/zellij/layouts/jimmyff.kdl'

# Tabs-only scaffold written by `mux init`; chrome is injected at launch by merge-layout.
const SCAFFOLD = 'layout {
    tab name="edit" {
        pane
    }
    tab name="git" {
        pane
    }
}
'

# --- layout injection -------------------------------------------------------

# Extract a balanced `<keyword> { ... }` block from KDL text, or "" if absent.
def extract-block [text: string, keyword: string] {
    let start = ($text | str index-of $keyword)
    if $start < 0 {
        return ""
    }
    mut depth = 0
    mut seen = false
    mut out = ""
    for c in ($text | str substring $start.. | split chars) {
        $out = $out + $c
        if $c == "{" {
            $depth = $depth + 1
            $seen = true
        } else if $c == "}" {
            $depth = $depth - 1
            if $seen and ($depth == 0) {
                break
            }
        }
    }
    $out
}

# Merge a project layout with the canonical bar chrome: strip any default_tab_template
# the project carries (defensive — handles stale frozen copies) and inject jimmyff's.
def merge-layout [project_layout: string] {
    let canonical = ($DEFAULT_LAYOUT | path expand)
    let template = (extract-block (open --raw $canonical) "default_tab_template")
    if ($template | is-empty) {
        error make { msg: $"mux: no default_tab_template in ($canonical)" }
    }
    let raw = (open --raw $project_layout)
    let existing = (extract-block $raw "default_tab_template")
    let stripped = (if ($existing | is-empty) { $raw } else { $raw | str replace $existing "" })
    $stripped | str replace "layout {" $"layout {\n    ($template)"
}

# --- resolution -------------------------------------------------------------

# ~/Projects/<name>/workspace[/…] → { session: <name>, root: …/workspace }
def project-workspace [] {
    let prefix = $"($env.HOME)/Projects/"
    if not ($env.PWD | str starts-with $prefix) {
        return null
    }
    let rel = ($env.PWD | str replace $prefix "" | path split)
    if (($rel | length) >= 2) and (($rel | get 1) == "workspace") {
        let name = ($rel | get 0)
        {
            session: $name,
            root: ([$env.HOME "Projects" $name "workspace"] | path join),
        }
    } else {
        null
    }
}

# git toplevel of the cwd, or null when not in a repo
def git-root [] {
    let res = (do -i { ^git rev-parse --show-toplevel | complete })
    if ($res != null) and ($res.exit_code == 0) {
        $res.stdout | str trim
    } else {
        null
    }
}

# session names must be [A-Za-z0-9_-]; collapse runs and strip edge dashes
def sanitize [name: string] {
    $name
    | str replace --all --regex '[^A-Za-z0-9_-]' '-'
    | str replace --all --regex '-+' '-'
    | str trim --char '-'
}

# nearest .zellij.kdl walking from cwd up to (and including) root, else null
def find-layout [root: string] {
    if ($env.ZJ_LAYOUT? | is-not-empty) {
        return $env.ZJ_LAYOUT
    }
    mut dir = $env.PWD
    loop {
        let candidate = ([$dir ".zellij.kdl"] | path join)
        if ($candidate | path exists) {
            return $candidate
        }
        if $dir == $root {
            break
        }
        let parent = ($dir | path dirname)
        if $parent == $dir {
            break
        }
        $dir = $parent
    }
    null
}

# { session, root, layout } resolved from cwd; first match wins
def resolve [] {
    let picked = (
        if ($env.ZJ_SESSION? | is-not-empty) {
            { session: $env.ZJ_SESSION, root: $env.PWD }
        } else {
            let proj = (project-workspace)
            if ($proj != null) {
                $proj
            } else {
                let gr = (git-root)
                if ($gr != null) {
                    { session: ($gr | path basename), root: $gr }
                } else {
                    { session: ($env.PWD | path basename), root: $env.PWD }
                }
            }
        }
    )
    let session = (sanitize $picked.session)
    if ($session | is-empty) {
        error make { msg: $"mux: could not derive a valid session name from ($env.PWD)" }
    }
    {
        session: $session,
        root: $picked.root,
        layout: (find-layout $picked.root),
    }
}

# --- zellij helpers ---------------------------------------------------------

# running + EXITED session names (clean, one per line); [] on any failure
def zellij-sessions [] {
    let res = (do -i { ^zellij list-sessions -ns | complete })
    if ($res == null) or ($res.exit_code != 0) {
        return []
    }
    $res.stdout | lines | str trim | where {|l| $l | is-not-empty }
}

# attach if the session exists (running or resurrectable), else create it
def launch [r: record] {
    cd $r.root
    if ($r.session in (zellij-sessions)) {
        # attach (running) or resurrect (exited); --create guards against a race/miss
        ^zellij attach --create $r.session
    } else if ($r.layout != null) {
        # Inject the canonical bar chrome (jimmyff.kdl) into the project's tabs-only
        # layout at launch, so every new session tracks the single source of truth.
        let merged = (($env.TMPDIR? | default "/tmp") | path join $"mux-($r.session).kdl")
        merge-layout $r.layout | save -f $merged
        # --new-session-with-layout (NOT --layout): the latter + --session is read as
        # "add tabs to an existing session" and errors when the session doesn't exist
        ^zellij --session $r.session --new-session-with-layout $merged
    } else {
        ^zellij --session $r.session
    }
}

# --- entry points -----------------------------------------------------------

def main [] {
    let r = (resolve)
    if ($env.ZELLIJ? | is-not-empty) {
        let current = ($env.ZELLIJ_SESSION_NAME? | default "")
        if $current == $r.session {
            print $"Already in session '($r.session)'."
        } else {
            print $"In session '($current)'. Toggle with Ctrl g, then Ctrl o w to switch to '($r.session)'."
        }
    } else {
        launch $r
    }
}

def "main reset" [] {
    if ($env.ZELLIJ? | is-not-empty) {
        error make { msg: "mux reset: run from outside a zellij session." }
    }
    let r = (resolve)
    if ($r.session in (zellij-sessions)) {
        ^zellij delete-session $r.session --force
    }
    launch $r
}

def "main init" [] {
    let target = ([$env.PWD ".zellij.kdl"] | path join)
    if ($target | path exists) {
        error make { msg: $"mux init: ($target) already exists — refusing to overwrite." }
    }
    # Tabs-only scaffold; bar chrome is injected from jimmyff.kdl at launch (merge-layout).
    $SCAFFOLD | save $target
    print $"Wrote ($target)"
}
