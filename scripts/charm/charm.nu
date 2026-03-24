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
  let repo = ($result.repo | update path $result.path)
  let subs = $result.submodules

  let has_parent = if ($subs | is-empty) { false } else {
    ($subs | where { |s| $s.ahead_parent != $s.ahead_remote or $s.behind_parent != $s.behind_remote } | is-not-empty)
  }

  let repo_row = (format-git-row $repo $fetched true $has_parent)
  let sub_rows = ($subs | each { |r| format-git-row $r $fetched false $has_parent })
  let rows = ([$repo_row] | append $sub_rows)

  mut cols = ["package" "git"]
  if $has_parent { $cols = ($cols | append "parent") }
  $rows | select ...$cols | print
  print (format-readiness $result)
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
  let result = (charm git pull --path $path | from json)
  let warns = ($result.warnings? | default [])
  if (not ($warns | is-empty)) {
    for w in $warns { print $"(ansi yellow)warning:(ansi reset) ($w)" }
    print ""
  }
  print $"(ansi cyan_bold)Pulled:(ansi reset) ($result.branch)"
  let subs = ($result.submodules? | default [])
  if ($subs | is-empty) { return }
  $subs | each { |s|
    let status = if ($s.was_dirty? | default false) {
      $"(ansi yellow)skipped \(dirty\)(ansi reset)"
    } else if ($s.error? | default "") != "" {
      $"(ansi red)($s.error)(ansi reset)"
    } else if $s.new_commits > 0 {
      $"(ansi green)+($s.new_commits) commits(ansi reset)"
    } else {
      "up-to-date"
    }
    { path: $s.path, branch: $s.branch, status: $status }
  } | print
}

def "main git check" [--path: string = "." --skip-fetch --cached] {
  let extra_args = if $cached {
    [--cached]
  } else if $skip_fetch {
    [--skip-fetch]
  } else {
    []
  }
  let result = (charm git check --path $path ...$extra_args | from json)
  if $result.clean and ($result.issues | is-empty) {
    print $"(ansi green_bold)\u{2713} Ready(ansi reset) — fully committed and pushed"
    return
  }
  # Header with counts
  let s = $result.summary
  mut header_parts = []
  if $s.errors > 0 { $header_parts = ($header_parts | append $"(ansi red)($s.errors) error\(s\)(ansi reset)") }
  if $s.warns > 0 { $header_parts = ($header_parts | append $"(ansi yellow)($s.warns) warning\(s\)(ansi reset)") }
  if $s.infos > 0 { $header_parts = ($header_parts | append $"(ansi dark_gray)($s.infos) info\(s\)(ansi reset)") }
  print $"Git check: ($header_parts | str join ', ')"
  print ""
  # Per-issue lines
  for issue in $result.issues {
    let sev = if $issue.severity == "error" {
      $"(ansi red)\u{2717}(ansi reset)"
    } else if $issue.severity == "warn" {
      $"(ansi yellow)\u{26a0}(ansi reset)"
    } else {
      $"(ansi dark_gray)\u{2139}(ansi reset)"
    }
    let repo = if $issue.repo == "." { "(parent)" } else { $issue.repo }
    let fix = if ($issue.fix? | default "") != "" { $" (ansi dark_gray)fix: ($issue.fix)(ansi reset)" } else { "" }
    print $"  ($sev) ($repo): ($issue.message)($fix)"
  }
}

def "main git push" [--path: string = "."] {
  let result = (charm git push --path $path | from json)
  if ($result.error? | default "") != "" {
    print $"(ansi red_bold)Push aborted:(ansi reset) ($result.error)"
    return
  }
  let pushed = ($result.pushed? | default [])
  let failed = ($result.failed? | default [])
  let skipped = ($result.skipped? | default [])
  if ($pushed | is-empty) and ($failed | is-empty) {
    print "Nothing to push — all repos are up-to-date."
    return
  }
  if (not ($pushed | is-empty)) {
    for r in $pushed {
      let name = if $r.path == "." { "(parent)" } else { $r.path }
      print $"  (ansi green)\u{2713}(ansi reset) ($name) pushed"
    }
  }
  if (not ($failed | is-empty)) {
    for r in $failed {
      let name = if $r.path == "." { "(parent)" } else { $r.path }
      print $"  (ansi red)\u{2717}(ansi reset) ($name) failed: ($r.error)"
    }
  }
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
  # Show behind counts if we fetched live or have cached data from a fetched run
  let fetched = $fetch or ($git.timestamp? != null)

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

  # Build unified table
  let subs = $git.submodules
  let sub_paths = ($subs | get path)

  let has_parent = if ($subs | is-empty) { false } else {
    ($subs | where { |s| $s.ahead_parent != $s.ahead_remote or $s.behind_parent != $s.behind_remote } | is-not-empty)
  }

  # Repo row
  let repo = ($git.repo | update path $git.path)
  let repo_base = (format-git-row $repo $fetched true $has_parent)
  mut repo_row = $repo_base
  if $has_tests {
    $repo_row = ($repo_row | insert tests (aggregate-tests-repo $sub_paths $test_data.packages))
  }
  if $has_analyze {
    $repo_row = ($repo_row | insert analyze (aggregate-analyze-repo $sub_paths $analyze_data.packages))
  }

  # Submodule rows
  let sub_rows = ($subs | each { |r|
    mut row = (format-git-row $r $fetched false $has_parent)
    if $has_tests {
      $row = ($row | insert tests (aggregate-tests $r.path $test_data.packages))
    }
    if $has_analyze {
      $row = ($row | insert analyze (aggregate-analyze $r.path $analyze_data.packages))
    }
    $row
  })

  let rows = ([$repo_row] | append $sub_rows)

  mut cols = ["package" "git"]
  if $has_parent { $cols = ($cols | append "parent") }
  if $has_tests { $cols = ($cols | append "tests") }
  if $has_analyze { $cols = ($cols | append "analyze") }
  $rows | select ...$cols | print

  # Footer: readiness + staleness
  print-footer $git $test_data $analyze_data $path

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
  git check      Verify everything is committed, pushed, and refs in sync
  git push       Push all repos with unpushed commits
  git diff       Structured diff summary (staged/unstaged/untracked)
  git commit-sub Commit and push a single submodule
  git commit-parent  Stage submodule refs, commit and push parent
  git pull       Pull parent, checkout branches, pull all submodules
  overview       Combined dashboard: git + cached test/analyze (table)
  recache        Refresh git/test/analyze caches
  clean          Remove old session directories

Common flags: --path <dir> --filter <name>"
}

# --- Helpers ---

# Format a git status row for either repo or submodule (fields are now aligned)
def format-git-row [r: record, fetched: bool, is_repo: bool, has_parent: bool]: nothing -> record {
  let name = if $is_repo { $"(ansi cyan_bold)($r.path | path basename)(ansi reset)" } else { ($r.path | path basename) }
  let dirty = if $r.dirty { $" (ansi red)\u{25cf}(ansi reset)" } else { "" }
  let detached = ($r.detached? | default false)
  let branch = if $detached { $"(ansi red_bold)DETACHED(ansi reset)" } else { $r.branch }
  let ahead = ($r.ahead_remote? | default 0)
  let behind = ($r.behind_remote? | default 0)
  let tracking = (format-tracking $ahead $behind $fetched)
  let head_on = ($r.head_on_remote? | default true)
  let upstream = ($r.upstream? | default "")
  let stash = ($r.stash_count? | default 0)
  mut warnings = []
  if (not $head_on) { $warnings = ($warnings | append $"(ansi red_bold)NOT PUSHED(ansi reset)") }
  if $upstream == "" and (not $detached) and $r.branch != "" { $warnings = ($warnings | append $"(ansi yellow)no upstream(ansi reset)") }
  if $stash > 0 { $warnings = ($warnings | append $"(ansi yellow)($stash) stash(ansi reset)") }
  let warn_str = ($warnings | str join " ")
  mut row = {
    package: $"($name)($dirty)"
    git: ($"($branch) ($tracking) ($warn_str)" | str trim)
  }
  if $has_parent {
    let parent_val = if $is_repo { "" } else {
      (format-tracking ($r.ahead_parent? | default 0) ($r.behind_parent? | default 0) true)
    }
    $row = ($row | insert parent $parent_val)
  }
  $row
}

# Format ↑N ↓N tracking indicators (quiet when synced)
def format-tracking [ahead: int, behind: int, show_behind: bool]: nothing -> string {
  mut parts = []
  if $ahead > 0 { $parts = ($parts | append $"(ansi yellow)\u{2191}($ahead)(ansi reset)") }
  if $show_behind and $behind > 0 { $parts = ($parts | append $"(ansi red)\u{2193}($behind)(ansi reset)") }
  $parts | str join " "
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

# Aggregate test results for packages NOT under any submodule
def aggregate-tests-repo [sub_paths: list<string>, packages: list<record>]: nothing -> string {
  let matched = ($packages | where { |p| not ($sub_paths | any { |sp| ($p.path | str starts-with $sp) }) })
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

# Aggregate analyze results for packages NOT under any submodule
def aggregate-analyze-repo [sub_paths: list<string>, packages: list<record>]: nothing -> string {
  let matched = ($packages | where { |p| not ($sub_paths | any { |sp| ($p.path | str starts-with $sp) }) })
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

# Compute readiness verdict from git data (same rules as Go analyzeGitIssues)
# Returns a multi-line string with per-severity breakdown by type
def format-readiness [git_data: record]: nothing -> string {
  let repo = $git_data.repo
  let subs = ($git_data.submodules? | default [])

  # Count by type: { dirty: N, detached: N, ... }
  mut dirty = 0; mut detached = 0; mut unpushed = 0
  mut stash = 0; mut no_upstream = 0; mut ahead_parent = 0; mut behind_parent = 0

  # Parent checks
  if $repo.dirty { $dirty = $dirty + 1 }
  if ($repo.detached? | default false) { $detached = $detached + 1 }
  if ($repo.ahead_remote? | default 0) > 0 and (not ($repo.head_on_remote? | default true)) { $unpushed = $unpushed + 1 }
  if ($repo.stash_count? | default 0) > 0 { $stash = $stash + 1 }
  if ($repo.upstream? | default "") == "" and (not ($repo.detached? | default false)) and ($repo.branch? | default "") != "" { $no_upstream = $no_upstream + 1 }

  # Submodule checks
  for sub in $subs {
    if $sub.dirty { $dirty = $dirty + 1 }
    if ($sub.detached? | default false) { $detached = $detached + 1 }
    if ($sub.ahead_remote? | default 0) > 0 and (not ($sub.head_on_remote? | default true)) { $unpushed = $unpushed + 1 }
    if ($sub.stash_count? | default 0) > 0 { $stash = $stash + 1 }
    if ($sub.upstream? | default "") == "" and (not ($sub.detached? | default false)) and ($sub.branch? | default "") != "" { $no_upstream = $no_upstream + 1 }
    if ($sub.ahead_parent? | default 0) > 0 { $ahead_parent = $ahead_parent + 1 }
    if ($sub.behind_parent? | default 0) > 0 { $behind_parent = $behind_parent + 1 }
  }

  # Build error line (severity: error)
  mut error_parts = []
  if $dirty > 0 { $error_parts = ($error_parts | append $"($dirty) dirty") }
  if $detached > 0 { $error_parts = ($error_parts | append $"($detached) detached") }
  if $unpushed > 0 { $error_parts = ($error_parts | append $"($unpushed) unpushed") }

  # Build warn line (severity: warn)
  mut warn_parts = []
  if $stash > 0 { $warn_parts = ($warn_parts | append $"($stash) stash") }
  if $no_upstream > 0 { $warn_parts = ($warn_parts | append $"($no_upstream) no upstream") }
  if $ahead_parent > 0 { $warn_parts = ($warn_parts | append $"($ahead_parent) ahead of parent") }

  # Build info line (severity: info)
  mut info_parts = []
  if $behind_parent > 0 { $info_parts = ($info_parts | append $"($behind_parent) behind parent") }

  if ($error_parts | is-empty) and ($warn_parts | is-empty) and ($info_parts | is-empty) {
    return $"(ansi green)\u{2713} Ready(ansi reset)"
  }

  mut lines = []
  if (not ($error_parts | is-empty)) { $lines = ($lines | append $"(ansi red)\u{2717} ($error_parts | str join ', ')(ansi reset)") }
  if (not ($warn_parts | is-empty)) { $lines = ($lines | append $"(ansi yellow)\u{26a0} ($warn_parts | str join ', ')(ansi reset)") }
  if (not ($info_parts | is-empty)) { $lines = ($lines | append $"(ansi dark_gray)\u{2139} ($info_parts | str join ', ')(ansi reset)") }
  $lines | str join "\n"
}

# Print footer with readiness verdict + staleness info
def print-footer [git_data: record, test_data: record, analyze_data: record, path: string] {
  # Readiness verdict
  if ($git_data.timestamp? != null) or (not ($git_data.submodules? | default [] | is-empty)) {
    print (format-readiness $git_data)
  }
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
