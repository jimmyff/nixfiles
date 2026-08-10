package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"path/filepath"
	"strings"
)

// GitSync fast-forwards each submodule worktree to the parent's pinned ref,
// staying on the tracked branch (never detaching). Forward-only: a worktree
// ahead of the pin is reported, never rewound — bumping the pin is `git commit
// --parent-only`'s job. Genuine divergence is an error, not a merge.
func GitSync(args []string) int {
	fs := flag.NewFlagSet("git sync", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	filter := fs.String("filter", "", "comma-separated submodule name filters")
	skipFetch := fs.Bool("skip-fetch", false, "skip fetching from remotes")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	filters := parseFilter(*filter)
	if includeParent, _ := splitParentFilter(filters); includeParent {
		logf("error: --filter . is not supported for git sync — the parent repo is the source of the pinned refs, not a sync target\n")
		return ExitUsage
	}

	submodulePaths, err := getSubmodulePaths(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	warnUnmatchedFilters(filters, submodulePaths, "submodule")
	submodulePaths = filterSubmodulePaths(submodulePaths, filters)

	out := GitSyncOutput{
		Path:       root,
		Success:    true,
		Submodules: []GitSyncSubmodule{},
		Warnings:   []string{},
	}
	changed := false
	for _, subPath := range submodulePaths {
		res := syncSubmodule(root, subPath, !*skipFetch)
		switch res.Action {
		case "synced", "reattached":
			changed = true
		case "diverged", "error":
			out.Success = false
		case "skipped_dirty":
			out.Warnings = append(out.Warnings, fmt.Sprintf("%s has uncommitted changes (skipped)", subPath))
		}
		out.Submodules = append(out.Submodules, res)
	}

	// Repo state changed — cached status is stale
	if changed {
		deleteCache(root, "git.json")
	}

	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if !out.Success {
		return ExitFailure
	}
	return ExitOK
}

// syncSubmodule converges one submodule worktree on the parent's pinned ref.
// Invariant: the worktree only ever moves TO the pin, and only by fast-forward
// (or a branch attach at the same/older commit) — never past it, never backwards.
func syncSubmodule(root, subPath string, fetch bool) GitSyncSubmodule {
	subDir := filepath.Join(root, subPath)
	res := GitSyncSubmodule{Path: subPath, Action: "error"}

	pin := getParentPin(root, subPath)
	if pin == "" {
		res.Error = "no pinned ref found in parent HEAD"
		return res
	}

	head, err := runGit(subDir, "rev-parse", "HEAD")
	if err != nil {
		res.Error = fmt.Sprintf("cannot resolve HEAD: %v", err)
		return res
	}
	res.FromRef = head
	branch, _ := runGit(subDir, "branch", "--show-current")
	res.Branch = branch

	if head == pin && branch != "" {
		res.Action = "in_sync"
		return res
	}

	// A checkout/merge under uncommitted changes risks clobbering them — skip.
	if entries, err := statusEntries(subDir); err == nil && len(entries) > 0 {
		res.Action = "skipped_dirty"
		return res
	}

	// The pin may have arrived via a parent merge/pull and not exist in the
	// submodule's clone yet.
	if fetch {
		progressf("  %s: fetching...\n", subPath)
		if _, err := runGitNet(subDir, "fetch", "origin"); err != nil {
			progressf("  warning: fetch failed for %s: %v\n", subPath, err)
		}
	}
	if _, err := runGit(subDir, "cat-file", "-e", pin+"^{commit}"); err != nil {
		res.Error = fmt.Sprintf("pinned ref %s not found in submodule — fetch failed or ref never pushed", shortRef(pin))
		return res
	}

	if branch == "" {
		return reattachToPin(root, subDir, res, pin)
	}

	// Attached: relate the worktree HEAD to the pin.
	pinOnly, headOnly := getRevListCount(subDir, pin, head)
	switch {
	case pinOnly > 0 && headOnly == 0:
		// Behind the pin — the incident case. Fast-forward the tracked branch.
		if _, err := runGit(subDir, "merge", "--ff-only", pin); err != nil {
			res.Error = fmt.Sprintf("fast-forward to %s failed: %v", shortRef(pin), err)
			return res
		}
		res.Action = "synced"
		res.ToRef = pin
		res.NewCommits = pinOnly
		progressf("  %s: fast-forwarded %s to pin %s (%d commits)\n", subPath, branch, shortRef(pin), pinOnly)
	case headOnly > 0 && pinOnly == 0:
		res.Action = "ahead"
		res.Hint = fmt.Sprintf("glittering git commit --parent-only --path %s %s", root, subPath)
	case headOnly > 0 && pinOnly > 0:
		res.Action = "diverged"
		res.Error = fmt.Sprintf("diverged from pinned ref %s (%d ahead / %d behind) — resolve manually in the submodule, then bump the pin with: glittering git commit --parent-only --path %s %s",
			shortRef(pin), headOnly, pinOnly, root, subPath)
	default:
		// rev-list failed (0/0 with differing refs is impossible for real commits)
		res.Error = fmt.Sprintf("cannot relate HEAD %s to pinned ref %s", shortRef(head), shortRef(pin))
	}
	return res
}

// reattachToPin attaches a detached submodule to the branch its pin lives on,
// landing exactly on the pin. Refuses when that branch is ahead of the pin —
// attaching would move the worktree past the pinned state.
func reattachToPin(root, subDir string, res GitSyncSubmodule, pin string) GitSyncSubmodule {
	branch := branchForCommit(subDir, pin)
	if branch == "" {
		res.Error = fmt.Sprintf("pinned ref %s is not on any origin branch — cannot reattach without detaching later; push the submodule branch first", shortRef(pin))
		return res
	}

	// Local branch tip if it exists, else the remote tip checkout would create it from.
	tip, err := runGit(subDir, "rev-parse", "--verify", "refs/heads/"+branch)
	if err != nil {
		tip, err = runGit(subDir, "rev-parse", "--verify", "refs/remotes/origin/"+branch)
		if err != nil {
			res.Error = fmt.Sprintf("cannot resolve tip of %s: %v", branch, err)
			return res
		}
	}
	if _, tipOnly := getRevListCount(subDir, pin, tip); tipOnly > 0 {
		res.Error = fmt.Sprintf("branch %s is %d commit(s) ahead of pinned ref %s — reattaching would move past the pin; run: glittering git pull --path %s (sync to tip), then bump the pin with: glittering git commit --parent-only", branch, tipOnly, shortRef(pin), root)
		return res
	}

	// tip is at or behind the pin, so setting the branch to the pin is a
	// fast-forward (or a no-op) — no commits are lost.
	if _, err := runGit(subDir, "checkout", "-B", branch, pin); err != nil {
		res.Error = fmt.Sprintf("checkout -B %s %s failed: %v", branch, shortRef(pin), err)
		return res
	}
	ensureUpstream(subDir, branch)

	res.Action = "reattached"
	res.Branch = branch
	res.ToRef = pin
	if res.FromRef != pin {
		if count, err := runGit(subDir, "rev-list", "--count", res.FromRef+".."+pin); err == nil {
			fmt.Sscanf(count, "%d", &res.NewCommits)
		}
	}
	progressf("  %s: reattached to %s at pin %s\n", res.Path, branch, shortRef(pin))
	return res
}

// ensureUpstream sets origin/<branch> as upstream when none is configured
// (checkout -B doesn't track), so later status/pull have a tracking ref.
func ensureUpstream(subDir, branch string) {
	if _, err := runGit(subDir, "rev-parse", "--abbrev-ref", branch+"@{upstream}"); err == nil {
		return
	}
	remote := "origin/" + branch
	if _, err := runGit(subDir, "rev-parse", "--verify", "refs/remotes/"+remote); err != nil {
		return
	}
	runGit(subDir, "branch", "--set-upstream-to="+remote, branch)
}

// getParentPin reads the submodule commit recorded in the parent's HEAD tree.
func getParentPin(root, subPath string) string {
	out, err := runGit(root, "ls-tree", "HEAD", subPath)
	if err != nil || out == "" {
		return ""
	}
	// Format: <mode> commit <sha>\t<path>
	fields := strings.Fields(out)
	if len(fields) >= 3 {
		return fields[2]
	}
	return ""
}

func shortRef(ref string) string {
	if len(ref) > 12 {
		return ref[:12]
	}
	return ref
}
