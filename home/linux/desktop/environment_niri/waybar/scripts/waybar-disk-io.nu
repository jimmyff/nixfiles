# Disk activity as waybar JSON: colour from IO pressure, throughput in the tooltip.

const interval = 2sec
const icon = "\u{f04e2}"
const sector_bytes = 512 # /proc/diskstats always counts 512-byte sectors
const warning_pressure = 10.0 # % of time tasks stalled on IO (10s average)
const critical_pressure = 30.0

# Whole physical disks only: no partitions, loop, zram, device-mapper or eMMC boot areas.
def disk-names [] {
    ls /sys/block | get name | path basename | where {|name| $name !~ '^(loop|ram|zram|dm-|md|sr)|boot\d+$' }
}

# Sectors read and written, summed across the given disks.
def read-sectors [disks: list<string>] {
    open --raw /proc/diskstats
    | lines
    | each { str trim | split row --regex '\s+' }
    | where {|fields| $fields.2 in $disks }
    | reduce --fold { read: 0, written: 0 } {|fields, total|
        { read: ($total.read + ($fields.5 | into int)), written: ($total.written + ($fields.9 | into int)) }
    }
}

# Pressure-stall 10s averages, e.g. { some: 1.2, full: 0.0 }.
def io-pressure [] {
    open --raw /proc/pressure/io
    | lines
    | parse --regex '^(?<kind>\w+) avg10=(?<avg10>[\d.]+)'
    | reduce --fold {} {|row, pressure| $pressure | insert $row.kind ($row.avg10 | into float) }
}

def rate [sectors: int] {
    $sectors * $sector_bytes / ($interval / 1sec) | into int | into filesize
}

let disks = (disk-names)
if ($disks | is-empty) { error make { msg: "No physical disks found in /sys/block" } }

mut previous = (read-sectors $disks)
loop {
    sleep $interval
    let current = (read-sectors $disks)
    let pressure = (io-pressure)
    let class = if $pressure.some >= $critical_pressure {
        "critical"
    } else if $pressure.some >= $warning_pressure {
        "warning"
    } else {
        "normal"
    }
    let tooltip = [
        $"Read   (rate ($current.read - $previous.read))/s"
        $"Write  (rate ($current.written - $previous.written))/s"
        $"IO pressure ($pressure.some)% · full ($pressure.full)% \(10s avg\)"
    ]
    print ({ text: $icon, tooltip: ($tooltip | str join "\n"), class: $class } | to json --raw)
    $previous = $current
}
