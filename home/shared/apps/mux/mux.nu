# mux — zellij workspace launcher (sessions = workspaces)
#
# Resolves a session name + root dir + private layout from the current directory,
# then attaches to (or creates) the matching zellij session.
#
#   mux         launch/attach the workspace for the current directory
#   mux reset   delete the resolved session then relaunch (escape a bad resurrection)
#   mux init    scaffold a .zellij.kdl layout in the current directory
#
# Overrides: $env.ZJ_SESSION (session name), $env.ZJ_LAYOUT (layout name or path).
#
# Only `const`/`def` at top level — so `nu -c 'source mux.nu'` parse-checks without running.

const SCAFFOLD = 'layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        children
        pane size=1 borderless=true {
            plugin location="zellij:status-bar"
        }
    }
    tab name="edit" {
        pane
    }
    tab name="git" {
        pane
    }
}
'

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
        # --new-session-with-layout (NOT --layout): the latter + --session is read as
        # "add tabs to an existing session" and errors when the session doesn't exist
        ^zellij --session $r.session --new-session-with-layout $r.layout
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
    $SCAFFOLD | save $target
    print $"Wrote ($target)"
}
