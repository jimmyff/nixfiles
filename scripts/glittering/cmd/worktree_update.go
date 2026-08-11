package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"strings"
)

// worktreeUpdate brings the project's base branch into a feature worktree:
// fast-forward the base worktree to origin, merge it into the feature worktree,
// then reconverge submodule pins on both sides. Integration is a merge, never a
// rebase — feature branches may already be pushed. A conflict is left in
// progress by design: the agent resolves it, commits, and re-runs.
func worktreeUpdate(args []string) int {
	fs := flag.NewFlagSet("worktree update", flag.ExitOnError)
	path := fs.String("path", ".", "path inside the worktree to update")
	skipFetch := fs.Bool("skip-fetch", false, "skip fetching from remotes")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	proj, metas, target, code := resolveWorktreeCommand(*path)
	if code != ExitOK {
		return code
	}

	out := WorktreeUpdateOutput{
		Project: proj.ProjectName, ProjectDir: proj.ProjectDir,
		Worktree: target.Name, Path: target.Path, Branch: target.Branch,
		BaseBranch: proj.BaseBranch, Success: true,
		Base:       WorktreeBaseResult{Action: "missing", Submodules: []GitSyncSubmodule{}},
		Merge:      WorktreeMergeResult{Status: "skipped"},
		Submodules: []GitSyncSubmodule{},
		Reasons:    []string{}, Warnings: []string{},
	}
	base, hasBase := baseWorktree(metas, proj.BaseBranch)
	onBase := hasBase && base.Path == target.Path

	// Step 1 — fetch. Parent refs live in the shared common dir, so one fetch
	// serves every worktree; submodule clones are per-worktree.
	if !*skipFetch {
		progressf("  fetching origin...\n")
		if _, err := runGitNet(proj.CommonDir, "fetch", "origin"); err != nil {
			out.Warnings = append(out.Warnings, fmt.Sprintf("fetch failed: %v", err))
		}
		subs, _ := getSubmodulePaths(target.Path)
		fetchSubmodules(target.Path, subs)
		if hasBase && !onBase {
			baseSubs, _ := getSubmodulePaths(base.Path)
			fetchSubmodules(base.Path, baseSubs)
		}
	}

	// Step 2 — base worktree: fast-forward to origin, never rewind.
	if hasBase {
		out.Base = updateBaseWorktree(proj, base)
		switch out.Base.Action {
		case "skipped_dirty":
			out.Warnings = append(out.Warnings, fmt.Sprintf(
				"base worktree %s has uncommitted changes (not fast-forwarded); integrating its current tip", base.Name))
		case "failed":
			out.Success = false
			out.Warnings = append(out.Warnings, fmt.Sprintf(
				"base worktree %s could not be fast-forwarded: %s", base.Name, out.Base.Error))
		}
		if !syncResultsOK(out.Base.Submodules) {
			out.Success = false
		}
	} else {
		out.Warnings = append(out.Warnings, fmt.Sprintf(
			"no worktree on the base branch %q — integrating origin/%s directly", proj.BaseBranch, proj.BaseBranch))
	}

	if onBase {
		out.Warnings = append(out.Warnings, "running on the base worktree — only its fast-forward was performed")
		return finishUpdate(out)
	}

	// Step 3 — feature pre-flight: never merge over uncommitted work.
	if reasons := updateBlockers(target.Path); len(reasons) > 0 {
		out.Reasons = append(out.Reasons, reasons...)
		out.Success = false
		out.Hint = fmt.Sprintf("commit or stash the changes, then re-run: glittering worktree update --path %s", target.Path)
		return finishUpdate(out)
	}

	// Step 4 — merge the base branch in (its worktree's tip when it has one,
	// else origin's).
	mergeRef := proj.BaseBranch
	if !hasBase {
		mergeRef = "origin/" + proj.BaseBranch
	}
	out.Merge = mergeBaseIntoWorktree(target.Path, mergeRef)
	switch out.Merge.Status {
	case "conflicts":
		out.Success = false
		// Stage only what conflicted: `git add -A` re-stages every gitlink at its
		// submodule worktree's HEAD, discarding the pins this merge just brought in.
		out.Hint = fmt.Sprintf("resolve the conflicts and stage only those paths — `git add -A` would rewind any submodule pin this merge moved — then commit and re-run: glittering worktree update --path %s", target.Path)
		deleteCache(target.Path, "git.json")
		return finishUpdate(out)
	case "failed":
		out.Success = false
		return finishUpdate(out)
	}

	// Step 5 — pin convergence: the merge may have moved gitlinks. Submodules
	// were fetched in step 1, so this stays local.
	moved := out.Merge.Status == "merged"
	sync, err := syncSubmodules(target.Path, false, nil)
	if err != nil {
		out.Success = false
		out.Warnings = append(out.Warnings, fmt.Sprintf("submodule sync failed: %v", err))
	} else {
		out.Submodules = sync.Results
		out.Warnings = append(out.Warnings, sync.Warnings...)
		out.Success = out.Success && sync.OK
		moved = moved || sync.Changed
	}

	// Step 6 — a pin rewound by an earlier conflict resolution agrees with its
	// submodule worktree, so nothing above sees it. Catch it here, while the fix
	// is still local: at land time it becomes the base branch's problem.
	subPaths, _ := getSubmodulePaths(target.Path)
	for _, reg := range detectPinRegressions(target.Path, subPaths, baseRefs(proj.BaseBranch)) {
		out.Warnings = append(out.Warnings, reg.reason())
		if out.Hint == "" {
			out.Hint = reg.fix(target.Path)
		}
	}

	// Step 7 — anything moved ⇒ cached status is stale.
	if moved {
		deleteCache(target.Path, "git.json")
	}
	return finishUpdate(out)
}

// finishUpdate emits the output and maps it to an exit code.
func finishUpdate(out WorktreeUpdateOutput) int {
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if out.Hint != "" {
		logf("hint: %s\n", out.Hint)
	}
	if !out.Success {
		return ExitFailure
	}
	return ExitOK
}

// updateBaseWorktree fast-forwards the base worktree to origin/<base> and
// reconverges its submodule pins. The sync is part of the operation, not an
// afterthought: a fast-forward that moves a gitlink leaves the superproject
// dirty until the submodule worktree follows, which would then block the next
// update or land.
func updateBaseWorktree(proj projectInfo, base worktreeMeta) WorktreeBaseResult {
	res := WorktreeBaseResult{
		Name: base.Name, Path: base.Path, Branch: base.Branch,
		Submodules: []GitSyncSubmodule{},
	}
	head, err := runGit(base.Path, "rev-parse", "HEAD")
	if err != nil {
		res.Action, res.Error = "failed", fmt.Sprintf("cannot resolve HEAD: %v", err)
		return res
	}
	res.FromRef = head

	// File changes block a merge and are the user's to resolve; stale submodule
	// pins don't — the sync below heals those.
	subPaths, _ := getSubmodulePaths(base.Path)
	if entries, statusErr := statusEntries(base.Path); statusErr == nil && len(entries) > 0 {
		files := classifyParentFiles(entries, subPaths)
		if len(files.Staged)+len(files.Unstaged) > 0 {
			res.Action = "skipped_dirty"
			return res
		}
		if sync, syncErr := syncSubmodules(base.Path, false, nil); syncErr == nil {
			res.Submodules = sync.Results
		}
	}

	upstream := "origin/" + proj.BaseBranch
	if _, err := runGit(base.Path, "rev-parse", "--verify", "--quiet", "refs/remotes/"+upstream); err != nil {
		res.Action, res.Error = "failed", fmt.Sprintf("no %s ref — fetch failed or the base branch was never pushed", upstream)
		return res
	}
	progressf("  %s: fast-forwarding to %s...\n", base.Name, upstream)
	if _, err := runGit(base.Path, "merge", "--ff-only", upstream); err != nil {
		res.Action, res.Error = "failed", fmt.Sprintf("fast-forward to %s failed: %v", upstream, err)
		return res
	}
	newHead, _ := runGit(base.Path, "rev-parse", "HEAD")
	res.ToRef = newHead
	if newHead == head {
		res.Action = "up_to_date"
		return res
	}
	res.Action = "fast_forwarded"
	res.NewCommits = countCommits(base.Path, head, newHead)

	// The fast-forward may have moved gitlinks — converge before anything else
	// reads the base tree.
	if sync, syncErr := syncSubmodules(base.Path, false, nil); syncErr == nil {
		res.Submodules = sync.Results
	}
	deleteCache(base.Path, "git.json")
	return res
}

// updateBlockers lists reasons a worktree must not be merged into.
func updateBlockers(wtPath string) []string {
	if _, err := runGit(wtPath, "rev-parse", "--verify", "--quiet", "MERGE_HEAD"); err == nil {
		return []string{"a merge is already in progress — resolve the conflicts and commit it first"}
	}
	entries, err := statusEntries(wtPath)
	if err != nil {
		return []string{fmt.Sprintf("could not read worktree status: %v", err)}
	}
	if len(entries) == 0 {
		return nil
	}
	return []string{fmt.Sprintf("worktree has uncommitted changes (%s)", strings.Join(entryPaths(entries, 10), ", "))}
}

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

// unmergedPaths lists the paths a failed merge left conflicted (submodule
// gitlinks included).
func unmergedPaths(dir string) []string {
	out, err := runGit(dir, "diff", "--name-only", "--diff-filter=U")
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

// entryPaths lists status entry paths, capped so a large dirty tree can't
// produce an unreadable reason.
func entryPaths(entries []porcelainEntry, max int) []string {
	var paths []string
	for i, e := range entries {
		if i == max {
			paths = append(paths, fmt.Sprintf("+%d more", len(entries)-max))
			break
		}
		paths = append(paths, e.Path)
	}
	return paths
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
