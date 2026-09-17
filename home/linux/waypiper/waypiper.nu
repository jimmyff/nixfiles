# waypiper — show a remote host's GUI apps in this Wayland session (waypipe over ssh).
# Both ends need waypiper installed.

const PREFIX = "wayland-waypiper-"

# Link <host> to this Wayland session; reconnects until Ctrl-C
def main [host: string] {
    if ($env.WAYLAND_DISPLAY? | is-empty) {
        error make {msg: "waypiper needs a local Wayland session"}
    }
    let workstation = (sys host).hostname
    print $"linking ($host) → ($workstation); on ($host) use: waypiper run <cmd>"
    loop {
        # A dropped link can leave the old server holding the socket.
        if not (attempt { ^ssh $host waypiper clear $workstation }) { return }
        # dd exits when ssh closes stdin, so waypipe exits cleanly and removes its socket.
        if not (attempt { ^waypipe --no-gpu --display $"($PREFIX)($workstation)" ssh $host dd of=/dev/null status=none }) { return }
        print -e "link closed; reconnecting in 3s (Ctrl-C to stop)"
        sleep 3sec
    }
}

# Run an action, tolerating failure; false when a signal (e.g. Ctrl-C) stopped it.
def attempt [action: closure]: nothing -> bool {
    try { do $action; true } catch {|err| $err.details?.code? != "nu::shell::terminated_by_signal" }
}

# On the host: run <cmd> on a linked session
def --wrapped "main run" [--from: string, ...cmd: string] {
    if ($cmd | is-empty) {
        error make {msg: "usage: waypiper run [--from <workstation>] <cmd>"}
    }
    let links = open-links | where {|link| $from == null or $link == $"($PREFIX)($from)" }
    let display = match ($links | length) {
        1 => $links.0
        0 => { error make {msg: "no open link; run `waypiper <this host>` on your workstation"} }
        _ => { error make {msg: $"several links open, pick one with --from: ($links | str replace $PREFIX '' | str join ', ')"} }
    }
    with-env {WAYLAND_DISPLAY: $display} { run-external ...$cmd }
}

# On the host: drop a workstation's previous link
def "main clear" [workstation: string] {
    if $workstation !~ '^[A-Za-z0-9-]+$' {
        error make {msg: $"invalid workstation name: ($workstation)"}
    }
    let display = $"($PREFIX)($workstation)"
    try { ^pkill --full -- $"--display ($display) server" }
    rm --force ($env.XDG_RUNTIME_DIR | path join $display)
}

# Listening waypiper sockets in this user's runtime dir (ss shows waypipe's relative names).
def open-links []: nothing -> list<string> {
    ^ss --unix --listening --numeric --no-header
    | lines
    | each { split row --regex '\s+' | get 4 | path basename }
    | where {|name| ($name | str starts-with $PREFIX) and ($env.XDG_RUNTIME_DIR | path join $name | path exists) }
    | uniq
}
