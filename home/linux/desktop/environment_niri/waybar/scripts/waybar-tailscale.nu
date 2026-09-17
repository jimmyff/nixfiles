# Tailnet state as waybar JSON; hidden on hosts without tailscale.

let tailscale = "/run/current-system/sw/bin/tailscale"
let icon = "\u{f0582}"

def emit [text: string, tooltip: string, class: string] {
    print ({ text: $text, tooltip: $tooltip, class: $class } | to json --raw)
}

if not ($tailscale | path exists) { emit "" "" "absent"; exit }

let status = try { ^$tailscale status --json | from json } catch { null }
if $status == null { emit $icon "tailscaled not running" "critical"; exit }

match $status.BackendState {
    "Running" if not ($status.Self.Online? | default false) => {
        let health = ($status.Health? | default [])
        emit $icon (["Offline: can't reach Tailscale" ...$health] | str join "\n") "critical"
    }
    "Running" => {
        let peers = ($status.Peer? | default {} | values)
        let online = ($peers | where Online | length)
        let exit_node = ($peers | where ExitNode | get -o 0.HostName)
        let lines = [
            $"($status.Self.HostName) · ($status.Self.TailscaleIPs.0)"
            $"($online)/($peers | length) peers online"
            ...(if $exit_node != null { [$"Exit node: ($exit_node)"] } else { [] })
        ]
        emit $icon ($lines | str join "\n") (if $exit_node != null { "exit-node" } else { "connected" })
    }
    "Stopped" => { emit $icon "Tailscale down" "stopped" }
    $state => { emit $icon $"Tailscale: ($state)" "warning" }
}
