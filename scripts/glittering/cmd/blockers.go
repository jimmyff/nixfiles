package cmd

// Blocker and sync-result utilities shared by the worktree pre-flights
// (worktree_preflight.go) and the update/land commands that report them.

import "fmt"

// blockerReasons lists each blocker's prose refusal, in order — `reasons` is
// always derived from `blockers`, so the two channels cannot disagree.
func blockerReasons(blockers []Blocker) []string {
	var reasons []string
	for _, b := range blockers {
		reasons = append(reasons, b.Message)
	}
	return reasons
}

// firstHint returns the first non-empty blocker hint ("" when none has one).
func firstHint(blockers []Blocker) string {
	for _, b := range blockers {
		if b.Hint != "" {
			return b.Hint
		}
	}
	return ""
}

// appendHint adds a follow-up hint without dropping one already set — the
// first hint is the more urgent, the rest are follow-ups.
func appendHint(existing, add string) string {
	if existing == "" {
		return add
	}
	if add == "" {
		return existing
	}
	return existing + "; then: " + add
}

// mergeSyncResults folds two sync passes over the same worktree into one row
// per submodule: the pass that moved the worktree wins, and when both moved,
// the row spans them (pre's from_ref → post's to_ref, commits summed). Without
// this the post-merge sync's "in_sync" would erase the pre-flight heal.
func mergeSyncResults(pre, post []GitSyncSubmodule) []GitSyncSubmodule {
	if len(pre) == 0 {
		return post
	}
	moved := func(r GitSyncSubmodule) bool { return r.Action == "synced" || r.Action == "reattached" }
	preByPath := make(map[string]GitSyncSubmodule, len(pre))
	for _, r := range pre {
		preByPath[r.Path] = r
	}
	var out []GitSyncSubmodule
	seen := make(map[string]bool, len(post))
	for _, p := range post {
		seen[p.Path] = true
		prev, ok := preByPath[p.Path]
		switch {
		case !ok || !moved(prev):
			out = append(out, p)
		case !moved(p):
			out = append(out, prev)
		default:
			span := p
			span.FromRef = prev.FromRef
			span.NewCommits += prev.NewCommits
			out = append(out, span)
		}
	}
	for _, r := range pre {
		if !seen[r.Path] {
			out = append(out, r)
		}
	}
	return out
}

// syncResultsOK reports whether every submodule sync result is a good outcome
// (divergence and errors are not).
func syncResultsOK(results []GitSyncSubmodule) bool {
	for _, r := range results {
		if r.Action == "diverged" || r.Action == "error" {
			return false
		}
	}
	return true
}

// capPaths caps a path list so a large dirty tree can't produce an unreadable
// message.
func capPaths(paths []string, max int) []string {
	if len(paths) <= max {
		return paths
	}
	capped := append([]string{}, paths[:max]...)
	return append(capped, fmt.Sprintf("+%d more", len(paths)-max))
}

// entryPaths lists status entry paths, capped like capPaths.
func entryPaths(entries []porcelainEntry, max int) []string {
	var paths []string
	for _, e := range entries {
		paths = append(paths, e.Path)
	}
	return capPaths(paths, max)
}
