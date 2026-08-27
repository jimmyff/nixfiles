package cmd

import (
	"fmt"
	"path/filepath"
	"strings"
)

// mergeBaseIntoWorktree merges ref into the worktree at wtPath. On conflict the
// merge is deliberately left in progress and the unmerged paths are reported —
// a submodule path among them means two worktrees moved the same pin.
func mergeBaseIntoWorktree(wtPath, ref string) WorktreeMergeResult {
	res := WorktreeMergeResult{Ref: ref}
	head, err := runGit(wtPath, "rev-parse", "HEAD")
	if err != nil {
		res.Status, res.Error = "failed", fmt.Sprintf("cannot resolve HEAD: %v", err)
		return res
	}
	res.FromRef = head
	if _, err := runGit(wtPath, "rev-parse", "--verify", "--quiet", ref+"^{commit}"); err != nil {
		res.Status, res.Error = "failed", fmt.Sprintf("base ref %q not found", ref)
		return res
	}
	if _, err := runGit(wtPath, "merge-base", "--is-ancestor", ref, "HEAD"); err == nil {
		res.Status, res.ToRef = "up_to_date", head
		return res
	}
	res.CommitsIntegrated = countCommits(wtPath, "HEAD", ref)
	progressf("  merging %s (%d commits)...\n", ref, res.CommitsIntegrated)
	if _, err := runGit(wtPath, "merge", "--no-edit", ref); err != nil {
		if conflicts := unmergedPaths(wtPath); len(conflicts) > 0 {
			res.Status, res.Conflicts = "conflicts", conflicts
			res.Error = fmt.Sprintf("merge left in progress with %d conflicted path(s)", len(conflicts))
			return res
		}
		res.Status, res.Error = "failed", fmt.Sprintf("merge failed: %v", err)
		return res
	}
	newHead, _ := runGit(wtPath, "rev-parse", "HEAD")
	res.Status, res.ToRef = "merged", newHead
	return res
}

// gitPathLines runs a name-only git command and returns its non-empty lines.
func gitPathLines(dir string, args ...string) []string {
	out, err := runGit(dir, args...)
	if err != nil || out == "" {
		return nil
	}
	var paths []string
	for _, line := range strings.Split(out, "\n") {
		if p := strings.TrimSpace(line); p != "" {
			paths = append(paths, p)
		}
	}
	return paths
}

// unmergedPaths lists the paths a failed merge left conflicted (submodule
// gitlinks included).
func unmergedPaths(dir string) []string {
	return gitPathLines(dir, "diff", "--name-only", "--diff-filter=U")
}

// changedPubspecs lists pubspec.yaml files whose content differs between two
// commits — a dependency bump, which stales every pubspec.lock under it.
func changedPubspecs(dir, from, to string) []string {
	return filterPubspecs(gitPathLines(dir, "diff", "--name-only", from, to))
}

// filterPubspecs keeps exactly the pubspec.yaml paths.
func filterPubspecs(paths []string) []string {
	var pubspecs []string
	for _, p := range paths {
		if filepath.Base(p) == "pubspec.yaml" {
			pubspecs = append(pubspecs, p)
		}
	}
	return pubspecs
}
