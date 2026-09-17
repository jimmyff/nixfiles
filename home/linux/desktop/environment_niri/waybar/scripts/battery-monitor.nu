# Live battery power view from sysfs (no root).

const interval = 2sec
const window = 30 # samples in the rolling average

# Numeric sysfs attribute, or null when the driver doesn't expose it.
def read-attr [dir: path, name: string] {
    let file = ($dir | path join $name)
    if ($file | path exists) { open --raw $file | str trim | into float } else { null }
}

# Drivers report either energy (µWh, µW) or charge (µAh, µA); ratios work in either.
def read-battery [dir: path] {
    let energy = (read-attr $dir energy_now) != null
    let voltage = (read-attr $dir voltage_now)
    let rate = if $energy { read-attr $dir power_now } else { read-attr $dir current_now } | math abs
    {
        status: (open --raw ($dir | path join status) | str trim)
        capacity: (read-attr $dir capacity)
        stored: (read-attr $dir (if $energy { "energy_now" } else { "charge_now" }))
        full: (read-attr $dir (if $energy { "energy_full" } else { "charge_full" }))
        full_design: (read-attr $dir (if $energy { "energy_full_design" } else { "charge_full_design" }))
        cycles: (read-attr $dir cycle_count)
        rate: $rate
        watts: (if $energy { $rate / 1e6 } else { $rate * $voltage / 1e12 })
    }
}

def format-hours [hours: float] {
    let minutes = ($hours * 60 | math round | into int)
    $"($minutes // 60)h ($minutes mod 60 | fill --alignment right --width 2 --character '0')m"
}

let battery = (ls /sys/class/power_supply
    | get name
    | where { (open --raw ($in | path join type) | str trim) == "Battery" }
    | get -o 0)
if $battery == null { error make { msg: "No battery found in /sys/class/power_supply" } }

mut samples = []
loop {
    let now = (read-battery $battery)
    $samples = ($samples | append $now | last $window)
    let avg_rate = ($samples | get rate | math avg)
    let avg_watts = ($samples | get watts | math avg)

    let time_left = if $avg_rate <= 0 { "—" } else {
        match $now.status {
            "Discharging" => (format-hours ($now.stored / $avg_rate))
            "Charging" => $"(format-hours (($now.full - $now.stored) / $avg_rate)) to full"
            _ => "—"
        }
    }
    let health = ($now.full / $now.full_design * 100 | math round)
    let average_span = ($samples | length) * $interval

    clear
    print $"Battery    ($now.status) · ($now.capacity | into int)%"
    print $"Power      ($now.watts | math round --precision 1) W  \(avg ($avg_watts | math round --precision 1) W over ($average_span)\)"
    print $"Time left  ($time_left)"
    print $"Health     ($health)% · ($now.cycles | into int) cycles"
    print $"\n(ansi grey)Updates every ($interval) · Ctrl+C to quit(ansi reset)"
    sleep $interval
}
