package cmd

// Heal-then-classify pre-flight, shared by `worktree update` and `worktree
// land` on both the feature and the base worktree. Two phases, in order:
// (1) the forward-only submodule heal (`syncSubmodules`), which never rewinds
// a pin and never touches a dirty submodule, reported as *actions* in
// `submodules[]`; (2) classification of whatever dirt survives into structured
// Blockers. Only what a human must resolve becomes a refusal — a stale gitlink
// is not the user's work, it is a fixable (and now fixed) condition. This is
// why a conflicted `update` that was resolved and committed no longer
// deadlocks its own documented "re-run update" remedy.

import (
	"fmt"
	"path/filepath"
	"strings"
)

// preflightRequest describes one heal-then-classify pass over a worktree.
type preflightRequest struct {
	Path  string // worktree to pre-flight (absolute)
	Repo  string // Blocker.Repo: "." for the target worktree, else the base worktree's name
	Label string // how prose names it: "worktree" or "base worktree main"
	Fetch bool   // fetch inside each submodule during the heal
	ReRun string // exact command to re-run once blockers clear
}

// preflightResult is what the pre-flight did and what it still refuses on.
type preflightResult struct {
	Blockers   []Blocker          // never nil; empty ⇒ the worktree is ready
	Submodules []GitSyncSubmodule // never nil; what the heal did
	Changed    bool               // a submodule worktree moved ⇒ cached git.json is stale
}

// preflightWorktree heals stale submodule pins under req.Path, then classifies
// the dirt that survives. Writes nothing outside submodule worktrees, and only
// ever forward. A non-empty Blockers means "do not proceed".
func preflightWorktree(req preflightRequest) preflightResult {
	res := preflightResult{Blockers: []Blocker{}, Submodules: []GitSyncSubmodule{}}

	// A merge in progress owns the index (unmerged gitlink stages included);
	// syncing under it could check a submodule out from under a resolution in
	// flight. The one state the heal must not run in — check it first.
	if _, err := runGit(req.Path, "rev-parse", "--verify", "--quiet", "MERGE_HEAD"); err == nil {
		res.Blockers = append(res.Blockers, Blocker{
			Repo: req.Repo, Code: BlockerMergeInProgress,
			Message: labelPrefix(req) + "a merge is already in progress — resolve the conflicts and commit it first",
		})
		return res
	}

	// Heal: forward-only pin convergence. Sync's own warnings are dropped —
	// the classifier below reports the same dirt with a code and a remedy.
	sync, err := syncSubmodules(req.Path, req.Fetch, nil)
	if err != nil {
		res.Blockers = append(res.Blockers, Blocker{
			Repo: req.Repo, Code: BlockerStatusUnreadable,
			Message: fmt.Sprintf("%s: could not converge submodule pins: %v", req.Label, err),
		})
		return res
	}
	res.Submodules = sync.Results
	res.Changed = sync.Changed

	// Status AFTER the heal, so a converged gitlink no longer counts as dirt.
	// Untracked dirs expanded: the classifier needs files, not "dir/".
	entries, err := statusEntriesAll(req.Path)
	if err != nil {
		res.Blockers = append(res.Blockers, Blocker{
			Repo: req.Repo, Code: BlockerStatusUnreadable,
			Message: fmt.Sprintf("could not read %s status: %v", req.Label, err),
		})
		return res
	}
	if len(entries) == 0 {
		return res
	}

	subPaths, _ := getSubmodulePaths(req.Path)
	res.Blockers = classifyDirt(req, entries, subPaths, sync.Results)
	return res
}

// classifyDirt turns a *healed* worktree's status into ordered blockers.
// Read-only. Order is deterministic: parent-file blockers, then one group per
// dirty submodule in getSubmodulePaths order, then anything unclassifiable.
func classifyDirt(req preflightRequest, entries []porcelainEntry, subPaths []string, sync []GitSyncSubmodule) []Blocker {
	var blockers []Blocker

	// Gitlink detection is exact set membership: git never lists files inside
	// a submodule in the parent's porcelain — they collapse into the gitlink.
	subSet := make(map[string]bool, len(subPaths))
	for _, s := range subPaths {
		subSet[s] = true
	}

	files := classifyParentFiles(entries, subPaths)
	parentFiles := append(append([]string{}, files.Staged...), files.Unstaged...)
	locks, others := splitLockfiles(parentFiles)
	if len(others) > 0 {
		blockers = append(blockers, Blocker{
			Repo: req.Repo, Code: BlockerUserChanges,
			Message: fmt.Sprintf("%s has uncommitted changes (%s)", req.Label, strings.Join(capPaths(others, 10), ", ")),
			Paths:   capPaths(others, 10),
			Hint:    "commit or stash the changes, then re-run: " + req.ReRun,
		})
	}
	if len(locks) > 0 {
		blockers = append(blockers, lockfileBlocker(req, req.Path, locks))
	}

	syncByPath := make(map[string]GitSyncSubmodule, len(sync))
	for _, r := range sync {
		syncByPath[r.Path] = r
	}
	classified := make(map[string]bool, len(entries))
	for _, p := range parentFiles {
		classified[p] = true
	}
	for _, e := range entries {
		if !subSet[e.Path] {
			continue
		}
		classified[e.Path] = true
	}
	for _, sub := range subPaths {
		for _, e := range entries {
			if e.Path == sub {
				blockers = append(blockers, classifySubmoduleEntry(req, e, syncByPath[sub])...)
			}
		}
	}

	// Fail closed: a porcelain shape the classifier did not account for is
	// still a refusal, never a silent pass into a merge.
	var leftover []string
	for _, e := range entries {
		if !classified[e.Path] {
			leftover = append(leftover, e.Path)
		}
	}
	if len(leftover) > 0 {
		blockers = append(blockers, Blocker{
			Repo: req.Repo, Code: BlockerStatusUnreadable,
			Message: fmt.Sprintf("%s has changes the pre-flight could not classify (%s)", req.Label, strings.Join(capPaths(leftover, 10), ", ")),
			Paths:   capPaths(leftover, 10),
		})
	}
	return blockers
}

// classifySubmoduleEntry classifies one dirty gitlink, given the heal's
// verdict for that path. Returns nil only when nothing survives — which the
// caller's fail-closed guard would catch as a logic error anyway.
func classifySubmoduleEntry(req preflightRequest, e porcelainEntry, res GitSyncSubmodule) []Blocker {
	sub := e.Path

	// Index differs from HEAD with a clean worktree column: a staged pin
	// change (or a newly added submodule) waiting to be committed — the
	// user's pending work, not a convergence problem.
	if e.Y == ' ' {
		return []Blocker{{
			Repo: req.Repo, Code: BlockerUserChanges,
			Message: fmt.Sprintf("%s has a staged change to %s — commit it (glittering git commit --parent-only) or unstage it", req.Label, sub),
			Paths:   []string{sub},
		}}
	}

	switch res.Action {
	case "ahead":
		return []Blocker{{
			Repo: req.Repo, Code: BlockerSubmoduleAhead,
			Message: fmt.Sprintf("%s has commits the parent's pin doesn't include — bump the pin before integrating", sub),
			Paths:   []string{sub},
			Hint:    res.Hint, // sync already spells out `git commit --parent-only`
		}}
	case "diverged":
		return []Blocker{{
			Repo: req.Repo, Code: BlockerSubmoduleDiverged,
			Message: fmt.Sprintf("%s: %s", sub, res.Error), // sync's error carries the remedy
			Paths:   []string{sub},
		}}
	case "error":
		return []Blocker{{
			Repo: req.Repo, Code: BlockerSubmoduleUnsynced,
			Message: fmt.Sprintf("%s: %s", sub, res.Error),
			Paths:   []string{sub},
			Hint:    res.Hint,
		}}
	}

	// Pin is fine (in_sync/synced/reattached) or the heal skipped a dirty
	// worktree — either way the residual dirt lives inside the submodule.
	subEntries, err := statusEntriesAll(filepath.Join(req.Path, sub))
	if err != nil || len(subEntries) == 0 {
		// The parent reports it modified but we cannot see why — fail closed.
		detail := "its own status is clean"
		if err != nil {
			detail = fmt.Sprintf("its status is unreadable: %v", err)
		}
		return []Blocker{{
			Repo: req.Repo, Code: BlockerStatusUnreadable,
			Message: fmt.Sprintf("%s: the parent reports it modified but %s", sub, detail),
			Paths:   []string{sub},
		}}
	}
	var paths []string
	for _, se := range subEntries {
		paths = append(paths, sub+"/"+se.Path)
	}
	locks, others := splitLockfiles(paths)
	var blockers []Blocker
	if len(others) > 0 {
		blockers = append(blockers, Blocker{
			Repo: req.Repo, Code: BlockerSubmoduleDirty,
			Message: fmt.Sprintf("%s has uncommitted changes inside the submodule (%s)", sub, strings.Join(capPaths(others, 10), ", ")),
			Paths:   capPaths(others, 10),
			Hint:    fmt.Sprintf("commit or stash the changes in %s, then re-run: %s", sub, req.ReRun),
		})
	}
	if len(locks) > 0 {
		blockers = append(blockers, lockfileBlocker(req, filepath.Join(req.Path, sub), locks))
	}
	return blockers
}

// lockfileBlocker is the stale_lockfiles refusal: generated churn from a
// dependency bump, safe to regenerate and commit — not hand-written work.
func lockfileBlocker(req preflightRequest, getPath string, locks []string) Blocker {
	return Blocker{
		Repo: req.Repo, Code: BlockerStaleLockfiles,
		Message: fmt.Sprintf("%s has %d regenerated lockfile(s) uncommitted (%s) — generated churn from a dependency bump, not hand-written work",
			req.Label, len(locks), strings.Join(capPaths(locks, 10), ", ")),
		Paths: capPaths(locks, 10),
		Hint:  fmt.Sprintf("glittering get --path %s — then commit the regenerated pubspec.lock files", getPath),
	}
}

// splitLockfiles partitions paths into generated pubspec.lock files and
// everything else.
func splitLockfiles(paths []string) (locks, others []string) {
	for _, p := range paths {
		if isLockfile(p) {
			locks = append(locks, p)
		} else {
			others = append(others, p)
		}
	}
	return locks, others
}

// isLockfile reports whether a repo-relative path is a generated pubspec.lock.
func isLockfile(path string) bool {
	return filepath.Base(path) == "pubspec.lock"
}

// labelPrefix names the worktree in a message only when it is not the target
// itself — "worktree: ..." would be noise, "base worktree main: ..." is not.
func labelPrefix(req preflightRequest) string {
	if req.Repo == "." {
		return ""
	}
	return req.Label + ": "
}
