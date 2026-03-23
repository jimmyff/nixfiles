#!/usr/bin/env nu

# charm.nu — Nushell wrapper for charm with formatted table output

def "main status" [--path: string = "." --filter: string = ""] {
  let args = (build-args $path $filter)
  let result = (charm status ...$args | from json)
  $result.packages | select path name type has_tests dependencies dev_dependencies
}

def "main test" [--path: string = "." --filter: string = "" --timeout: int = 60] {
  let args = (build-args $path $filter)
  let result = (charm test ...$args --timeout $timeout | from json)
  $result.packages | select path runner status total passed failed skipped
  let failures = ($result.packages | where status != "pass" | where details_file? != null)
  if (not ($failures | is-empty)) {
    print ""
    print "Detail files:"
    $failures | each { |r| print $"  ($r.details_file)" }
  }
}

def "main analyze" [--path: string = "." --filter: string = ""] {
  let args = (build-args $path $filter)
  let result = (charm analyze ...$args | from json)
  $result.packages | select path status errors warnings infos
  let issues = ($result.packages | where status != "pass" | where details_file? != null)
  if (not ($issues | is-empty)) {
    print ""
    print "Detail files:"
    $issues | each { |r| print $"  ($r.details_file)" }
  }
}

def "main get" [--path: string = "." --filter: string = ""] {
  let args = (build-args $path $filter)
  let result = (charm get ...$args | from json)
  $result.packages | select path runner status
}

def "main upgrade" [--path: string = "." --filter: string = ""] {
  let args = (build-args $path $filter)
  let result = (charm upgrade ...$args | from json)
  $result.packages | select path runner status
}

def "main git" [--path: string = "." --skip-fetch --cached] {
  if $skip_fetch and $cached {
    print -e "error: --cached and --skip-fetch are mutually exclusive"
    return
  }
  let fetched = if $cached { false } else { not $skip_fetch }
  let extra_args = if $cached {
    [--cached]
  } else if $skip_fetch {
    [--skip-fetch]
  } else {
    []
  }
  let result = (charm git --path $path ...$extra_args | from json)
  let repo = $result.repo
  print-repo-line $repo $fetched
  let subs = $result.submodules
  if ($subs | is-empty) { return }
  print-sub-table $subs $fetched
}

def "main git commit-sub" [--path: string = "." --all -m: string sub_path: string] {
  mut args = [--path $path -m $m]
  if $all { $args = ($args | append [--all]) }
  $args = ($args | append [$sub_path])
  charm git commit-sub ...$args | from json
}

def "main git commit-parent" [--path: string = "." -m: string ...sub_paths: string] {
  let args = [--path $path -m $m ...$sub_paths]
  charm git commit-parent ...$args | from json
}

def "main git pull" [--path: string = "."] {
  charm git pull --path $path | from json
}

def "main git update" [--path: string = "."] {
  let result = (charm git update --path $path | from json)
  $result.submodules | select path new_commits
}

def "main git diff" [--path: string = "." --staged] {
  let extra_args = if $staged { [--staged] } else { [] }
  let result = (charm git diff --path $path ...$extra_args | from json)
  let repos = $result.repos
  if ($repos | is-empty) {
    print "No changes detected."
    return
  }
  let s = $result.summary
  print $"(ansi cyan_bold)Diff summary:(ansi reset) ($s.dirty_repos) dirty repo\(s\), ($s.total_files) files (ansi green)+($s.total_insertions)(ansi reset)/(ansi red)-($s.total_deletions)(ansi reset), ($s.total_untracked) untracked"
  $repos | each { |r|
    print ""
    let name = if $r.path == "." { "(parent)" } else { $r.path }
    print $"(ansi cyan_bold)($name)(ansi reset) — ($r.total_files) files (ansi green)+($r.total_insertions)(ansi reset)/(ansi red)-($r.total_deletions)(ansi reset)"
    let staged_files = $r.staged
    if (not ($staged_files | is-empty)) {
      print $"  (ansi green)Staged:(ansi reset)"
      $staged_files | each { |f| print $"    ($f.status) ($f.path) (ansi green)+($f.insertions)(ansi reset)/(ansi red)-($f.deletions)(ansi reset)" }
    }
    let unstaged_files = $r.unstaged
    if (not ($unstaged_files | is-empty)) {
      print $"  (ansi yellow)Unstaged:(ansi reset)"
      $unstaged_files | each { |f| print $"    ($f.status) ($f.path) (ansi green)+($f.insertions)(ansi reset)/(ansi red)-($f.deletions)(ansi reset)" }
    }
    let untracked = $r.untracked_files
    if (not ($untracked | is-empty)) {
      print $"  (ansi red)Untracked:(ansi reset) ($untracked | length) files"
      $untracked | each { |f| print $"    ($f)" }
    }
    if ($r.details_file? != null) and ($r.details_file != "") {
      print $"  (ansi dark_gray)Patch: ($r.details_file)(ansi reset)"
    }
  }
  null
}

def "main overview" [--path: string = "." --fetch] {
  let fetched = $fetch
  let status = (charm status --path $path | from json)

  # Git: cached by default, live --skip-fetch as fallback, live fetch with --fetch
  let git = if $fetch {
    (charm git --path $path | from json)
  } else {
    let cached = (charm git --cached --path $path | from json)
    if ($cached.submodules | is-empty) and ($cached.timestamp? == null) {
      # No cache exists, fall back to live without fetch (clear timestamp so staleness doesn't show)
      charm git --skip-fetch --path $path | from json | update timestamp null
    } else {
      $cached
    }
  }

  # Test + analyze: always from cache
  let test_data = (charm test --cached --path $path | from json)
  let analyze_data = (charm analyze --cached --path $path | from json)

  let has_tests = ($test_data.packages | length) > 0
  let has_analyze = ($analyze_data.packages | length) > 0

  # Package summary
  let total = ($status.packages | length)
  let flutter = ($status.packages | where type == "flutter" | length)
  let dart = ($status.packages | where type == "dart" | length)
  let testable = ($status.packages | where has_tests == true | length)
  print $"Packages: ($total) \(($flutter) flutter, ($dart) dart, ($testable) testable\)"

  # Repo line
  print-repo-line $git.repo $fetched

  # Submodule table with optional test/analyze columns
  let subs = $git.submodules
  if ($subs | is-empty) { return }

  let has_parent = ($subs | where { |s| $s.ahead_parent > 0 or $s.behind_parent > 0 } | is-not-empty)
  let formatted = ($subs | each { |r|
    let name = ($r.path | path basename)
    let dirty = if $r.dirty { $" (ansi red)\u{25cf}(ansi reset)" } else { "" }
    let branch = if $r.detached { $"(ansi yellow)detached(ansi reset)" } else { $r.branch }
    let tracking = (format-tracking $r.ahead_remote $r.behind_remote $fetched)
    mut row = {
      package: $"($name)($dirty)"
      git: $"($branch) ($tracking)"
    }
    if $has_parent {
      $row = ($row | insert parent (format-tracking $r.ahead_parent $r.behind_parent true))
    }
    if $has_tests {
      $row = ($row | insert tests (aggregate-tests $r.path $test_data.packages))
    }
    if $has_analyze {
      $row = ($row | insert analyze (aggregate-analyze $r.path $analyze_data.packages))
    }
    $row
  })

  mut cols = ["package" "git"]
  if $has_parent { $cols = ($cols | append "parent") }
  if $has_tests { $cols = ($cols | append "tests") }
  if $has_analyze { $cols = ($cols | append "analyze") }
  $formatted | select ...$cols | print

  # Staleness indicators
  print-staleness $git $test_data $analyze_data $path

  if (not $fetched) and ($git.timestamp? == null) {
    print $"(ansi dark_gray)Run with --fetch for up-to-date remote tracking(ansi reset)"
  }
}

def "main recache" [--path: string = "." --force] {
  # Git (with fetch)
  if $force or (not (cache-fresh "git" $path 60)) {
    print "Refreshing git cache..."
    try { charm git --path $path out> /dev/null }
  } else {
    print $"(ansi dark_gray)Git cache is recent, skipping \(use --force to override\)(ansi reset)"
  }

  # Test
  if $force or (not (cache-fresh "test" $path 60)) {
    print "Refreshing test cache..."
    try { charm test --path $path out> /dev/null }
  } else {
    print $"(ansi dark_gray)Test cache is recent, skipping \(use --force to override\)(ansi reset)"
  }

  # Analyze
  if $force or (not (cache-fresh "analyze" $path 60)) {
    print "Refreshing analyze cache..."
    try { charm analyze --path $path out> /dev/null }
  } else {
    print $"(ansi dark_gray)Analyze cache is recent, skipping \(use --force to override\)(ansi reset)"
  }

  print "Done."
}

def "main clean" [] {
  charm clean
}

def main [] {
  print "charm.nu — Formatted Nushell wrapper for charm (tables, styled indicators)

Commands:
  status         List discovered packages (table)
  test           Run tests across all packages (table)
  analyze        Run dart analyze across all packages (table)
  get            Run pub get across all packages (table)
  upgrade        Run pub upgrade across all packages (table)
  git            Git status with styled indicators
  git diff       Structured diff summary (staged/unstaged/untracked)
  git commit-sub Commit and push a single submodule
  git commit-parent  Stage submodule refs, commit and push parent
  git pull       Pull parent repo and sync submodules
  git update     Pull latest in each submodule
  overview       Combined dashboard: git + cached test/analyze (table)
  recache        Refresh git/test/analyze caches
  clean          Remove old session directories

Common flags: --path <dir> --filter <name>"
}

# --- Helpers ---

# Print styled repo summary line
def print-repo-line [repo: record, fetched: bool] {
  let dirty = if $repo.dirty { $" (ansi red)\u{25cf}(ansi reset)" } else { "" }
  let tracking = (format-tracking $repo.ahead $repo.behind $fetched)
  print $"(ansi cyan_bold)Repo:(ansi reset) ($repo.branch)($dirty) ($tracking)"
}

# Print styled submodule table
def print-sub-table [subs: list<record>, fetched: bool] {
  let has_parent = ($subs | where { |s| $s.ahead_parent > 0 or $s.behind_parent > 0 } | is-not-empty)
  let formatted = ($subs | each { |r|
    let name = ($r.path | path basename)
    let dirty = if $r.dirty { $" (ansi red)\u{25cf}(ansi reset)" } else { "" }
    let branch = if $r.detached { $"(ansi yellow)detached(ansi reset)" } else { $r.branch }
    let tracking = (format-tracking $r.ahead_remote $r.behind_remote $fetched)
    mut row = {
      package: $"($name)($dirty)"
      git: $"($branch) ($tracking)"
    }
    if $has_parent {
      $row = ($row | insert parent (format-tracking $r.ahead_parent $r.behind_parent true))
    }
    $row
  })
  mut cols = ["package" "git"]
  if $has_parent { $cols = ($cols | append "parent") }
  $formatted | select ...$cols | print
}

# Format ↑N ↓N tracking indicators
def format-tracking [ahead: int, behind: int, show_behind: bool]: nothing -> string {
  let dim = (ansi dark_gray)
  let reset = (ansi reset)
  let a = if $ahead > 0 { $"(ansi yellow)\u{2191}($ahead)(ansi reset)" } else { $"($dim)\u{2191}\u{00b7}($reset)" }
  if (not $show_behind) {
    return $a
  }
  let b = if $behind > 0 { $"(ansi red)\u{2193}($behind)(ansi reset)" } else { $"($dim)\u{2193}\u{00b7}($reset)" }
  $"($a) ($b)"
}

# Aggregate test results for a submodule path
def aggregate-tests [sub_path: string, packages: list<record>]: nothing -> string {
  let matched = ($packages | where { |p| ($p.path | str starts-with $sub_path) })
  if ($matched | is-empty) { return "" }
  let cmd_errors = ($matched | where status == "error" | length)
  if $cmd_errors > 0 {
    return $"(ansi red)err(ansi reset)"
  }
  let total = ($matched | get total | math sum)
  let failed = ($matched | get failed | math sum)
  if $failed > 0 {
    $"(ansi red)\u{2717} ($failed)(ansi reset)"
  } else {
    $"(ansi green)\u{2713} ($total)(ansi reset)"
  }
}

# Aggregate analyze results for a submodule path
def aggregate-analyze [sub_path: string, packages: list<record>]: nothing -> string {
  let matched = ($packages | where { |p| ($p.path | str starts-with $sub_path) })
  if ($matched | is-empty) { return "" }
  let cmd_errors = ($matched | where status == "error" | length)
  let errors = ($matched | get errors | math sum)
  let warnings = ($matched | get warnings | math sum)
  let infos = ($matched | get infos | math sum)
  if $cmd_errors > 0 {
    $"(ansi red)err(ansi reset)"
  } else if $errors > 0 or $warnings > 0 {
    mut parts = []
    if $errors > 0 { $parts = ($parts | append $"(ansi red)($errors)e(ansi reset)") }
    if $warnings > 0 { $parts = ($parts | append $"(ansi yellow)($warnings)w(ansi reset)") }
    $parts | str join " "
  } else if $infos > 0 {
    $"(ansi dark_gray)($infos)i(ansi reset)"
  } else {
    $"(ansi green)\u{2713}(ansi reset)"
  }
}

# Format age as human-readable string
def format-age [timestamp: string]: nothing -> string {
  let ts = ($timestamp | into datetime)
  let now = (date now)
  let mins = (($now - $ts) / 1min | math floor)
  if $mins < 60 {
    $"($mins)min"
  } else {
    let hrs = ($mins / 60 | math floor)
    if $hrs < 24 {
      $"($hrs)hr"
    } else {
      let days = ($hrs / 24 | math floor)
      $"($days) days"
    }
  }
}

# Print staleness info below the overview table
def print-staleness [git_data: record, test_data: record, analyze_data: record, path: string] {
  mut parts = []
  mut warnings = []
  mut missing = []

  if ($git_data.timestamp? != null) {
    let age = (format-age $git_data.timestamp)
    let ts = ($git_data.timestamp | into datetime)
    if ((date now) - $ts) > 48hr {
      $warnings = ($warnings | append $"Git data is ($age) old")
    } else {
      $parts = ($parts | append $"Git ($age) ago")
    }
  }

  if ($test_data.timestamp? != null) {
    let age = (format-age $test_data.timestamp)
    let ts = ($test_data.timestamp | into datetime)
    if ((date now) - $ts) > 48hr {
      $warnings = ($warnings | append $"Test results are ($age) old")
    } else {
      $parts = ($parts | append $"Tests ($age) ago")
    }
  } else {
    $missing = ($missing | append "test")
  }

  if ($analyze_data.timestamp? != null) {
    let age = (format-age $analyze_data.timestamp)
    let ts = ($analyze_data.timestamp | into datetime)
    if ((date now) - $ts) > 48hr {
      $warnings = ($warnings | append $"Analysis is ($age) old")
    } else {
      $parts = ($parts | append $"Analysis ($age) ago")
    }
  } else {
    $missing = ($missing | append "analyze")
  }

  if (not ($parts | is-empty)) {
    let sep = $" \u{00b7} "
    print $"(ansi dark_gray)($parts | str join $sep)(ansi reset)"
  }
  if (not ($warnings | is-empty)) {
    print $"(ansi yellow)($warnings | str join ' \u{00b7} ') — run: charm.nu recache --path ($path)(ansi reset)"
  }
  if (not ($missing | is-empty)) {
    print $"(ansi dark_gray)No cached ($missing | str join '/') data — run: charm.nu recache --path ($path)(ansi reset)"
  }
}

# Check if a cache kind is fresh (within threshold_min minutes)
def cache-fresh [kind: string, path: string, threshold_min: int]: nothing -> bool {
  let result = (charm $kind --cached --path $path | from json)
  if ($result.timestamp? == null) { return false }
  let ts = ($result.timestamp | into datetime)
  let age_min = (((date now) - $ts) / 1min | math floor)
  $age_min < $threshold_min
}

# Build --path and --filter args for charm
def build-args [path: string, filter: string]: nothing -> list<string> {
  mut args = [--path $path]
  if $filter != "" { $args = ($args | append [--filter $filter]) }
  $args
}
