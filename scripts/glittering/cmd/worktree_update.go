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
		Reasons:    []string{}, Blockers: []Blocker{}, Warnings: []string{},
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
				"base worktree %s not fast-forwarded; integrating its current tip", base.Name))
			out.Warnings = append(out.Warnings, blockerReasons(out.Base.Blockers)...)
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

	// Step 3 — feature pre-flight: heal what a machine can (a merge that moved
	// a gitlink leaves the submodule behind its pin — not the user's problem),
	// then refuse only on what a human must resolve. Healing before the merge
	// is what unblocks the documented "resolve, commit, re-run" loop.
	pre := preflightWorktree(preflightRequest{
		Path: target.Path, Repo: ".", Label: "worktree", Fetch: false, // step 1 fetched already
		ReRun: fmt.Sprintf("glittering worktree update --path %s", target.Path),
	})
	out.Submodules = pre.Submodules
	if pre.Changed {
		deleteCache(target.Path, "git.json")
	}
	if len(pre.Blockers) > 0 {
		out.Blockers = pre.Blockers
		out.Reasons = append(out.Reasons, blockerReasons(pre.Blockers)...)
		out.Success = false
		out.Hint = firstHint(pre.Blockers)
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
	moved := out.Merge.Status == "merged" || pre.Changed
	sync, err := syncSubmodules(target.Path, false, nil)
	if err != nil {
		out.Success = false
		out.Warnings = append(out.Warnings, fmt.Sprintf("submodule sync failed: %v", err))
	} else {
		out.Submodules = mergeSyncResults(out.Submodules, sync.Results)
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

	// Step 7 — a merge that bumped a dependency version leaves every dependent
	// pubspec.lock stale; the first pub get/analyze/test regenerates them and
	// the tree is suddenly dirty at land time, far from its cause. Say so now,
	// while it is cheap. Update does not run pub get: it is a git operation.
	if out.Merge.Status == "merged" {
		if changed := changedPubspecs(target.Path, out.Merge.FromRef, out.Merge.ToRef); len(changed) > 0 {
			out.Warnings = append(out.Warnings, fmt.Sprintf(
				"the merge changed %d pubspec.yaml file(s) (%s) — dependency versions moved",
				len(changed), strings.Join(capPaths(changed, 5), ", ")))
			out.Hint = appendHint(out.Hint, fmt.Sprintf(
				"dependency versions changed — run `glittering get --path %s` and commit the regenerated pubspec.lock files now, before they surface as dirt at land time", target.Path))
		}
	}

	// Step 8 — anything moved ⇒ cached status is stale.
	if moved {
		deleteCache(target.Path, "git.json")
	}
	return finishUpdate(out)
}

// finishUpdate emits the output and maps it to an exit code.
func finishUpdate(out WorktreeUpdateOutput) int {
	// Empty lists, never null — callers index into these.
	if out.Blockers == nil {
		out.Blockers = []Blocker{}
	}
	if out.Submodules == nil {
		out.Submodules = []GitSyncSubmodule{}
	}
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

	// Heal-then-classify: stale submodule pins are converged (forward-only),
	// and only surviving dirt skips the fast-forward — the user's to resolve.
	pre := preflightWorktree(preflightRequest{
		Path: base.Path, Repo: base.Name,
		Label: fmt.Sprintf("base worktree %s", base.Name),
		Fetch: false, // the caller's step 1 already fetched this worktree's submodules
		ReRun: fmt.Sprintf("glittering worktree update --path %s", base.Path),
	})
	res.Submodules = pre.Submodules
	if pre.Changed {
		deleteCache(base.Path, "git.json")
	}
	if len(pre.Blockers) > 0 {
		res.Action, res.Blockers = "skipped_dirty", pre.Blockers
		return res
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
		res.Submodules = mergeSyncResults(res.Submodules, sync.Results)
	}
	deleteCache(base.Path, "git.json")
	return res
}
