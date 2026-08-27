package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
)

// worktreeLand publishes a feature worktree and fast-forwards the base branch
// onto it: pre-flight, push submodules then the feature branch, fast-forward
// the base worktree and push it. Fast-forward only — the base branch never
// moves to a commit that doesn't already contain it, so landing cannot
// conflict; anything else is a refusal with `worktree update` as the remedy.
// Never removes the worktree — that is `worktree prune`'s job.
func worktreeLand(args []string) int {
	fs := flag.NewFlagSet("worktree land", flag.ExitOnError)
	path := fs.String("path", ".", "path inside the worktree to land")
	allowPinRewind := fs.Bool("allow-pin-rewind", false, "land even where it moves a submodule pin backwards (deliberate reverts)")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	proj, metas, target, code := resolveWorktreeCommand(*path)
	if code != ExitOK {
		return code
	}

	out := WorktreeLandOutput{
		Project: proj.ProjectName, ProjectDir: proj.ProjectDir,
		Worktree: target.Name, Path: target.Path, Branch: target.Branch,
		BaseBranch: proj.BaseBranch,
		Base:       WorktreeBaseResult{Action: "missing", Submodules: []GitSyncSubmodule{}},
		Reasons:    []string{}, Blockers: []Blocker{}, Submodules: []GitSyncSubmodule{},
		Warnings: []string{},
		Pushed:   []PushRepoResult{}, Skipped: []PushRepoResult{}, Failed: []PushRepoResult{},
	}

	// Shape refusals: nothing to land, or nowhere to land it.
	base, hasBase := baseWorktree(metas, proj.BaseBranch)
	var shape []Blocker
	switch {
	case !hasBase:
		shape = append(shape, Blocker{Repo: ".", Code: BlockerNotLandable, Message: fmt.Sprintf(
			"no worktree on the base branch %q — land fast-forwards it, so it must be checked out", proj.BaseBranch)})
	case base.Path == target.Path:
		shape = append(shape, Blocker{Repo: ".", Code: BlockerNotLandable,
			Message: "refusing to land the base worktree into itself"})
	}
	if target.Branch == "" {
		shape = append(shape, Blocker{Repo: ".", Code: BlockerNotLandable,
			Message: "worktree is in detached HEAD state — nothing to land"})
	}
	if len(shape) > 0 {
		out.Blockers = shape
		out.Reasons = append(out.Reasons, blockerReasons(shape)...)
		return finishLand(out)
	}
	out.Base = WorktreeBaseResult{
		Name: base.Name, Path: base.Path, Branch: base.Branch,
		Action: "missing", Submodules: []GitSyncSubmodule{},
	}

	// Phase 1 — fetch, once and in parallel. Parent refs live in the shared
	// common dir, so one fetch refreshes the remote-tracking refs the
	// containment checks read; submodule clones are per-worktree.
	progressf("  fetching origin...\n")
	if _, err := runGitNet(target.Path, "fetch", "origin"); err != nil {
		out.Warnings = append(out.Warnings, fmt.Sprintf("fetch failed: %v", err))
	}
	subs, _ := getSubmodulePaths(target.Path)
	fetchSubmodules(target.Path, subs)
	if base.Branch == proj.BaseBranch {
		baseSubs, _ := getSubmodulePaths(base.Path)
		fetchSubmodules(base.Path, baseSubs)
	}

	// Phase 2 — heal both worktrees before anything is measured: a heal moves
	// a submodule worktree, which changes its ahead/behind counts — measuring
	// first could let land publish a parent commit that references an unpushed
	// submodule commit. The base heal is gated on its branch: never converge
	// submodules onto a wrong branch's pins.
	pre := preflightWorktree(preflightRequest{
		Path: target.Path, Repo: ".", Label: "worktree", Fetch: false,
		ReRun: fmt.Sprintf("glittering worktree land --path %s", target.Path),
	})
	out.Submodules = pre.Submodules
	if pre.Changed {
		deleteCache(target.Path, "git.json")
	}
	var basePre preflightResult
	if base.Branch == proj.BaseBranch {
		basePre = preflightWorktree(preflightRequest{
			Path: base.Path, Repo: base.Name,
			Label: fmt.Sprintf("base worktree %s", base.Name), Fetch: false,
			ReRun: fmt.Sprintf("glittering worktree land --path %s", target.Path),
		})
		out.Base.Submodules = basePre.Submodules
		if basePre.Changed {
			deleteCache(base.Path, "git.json")
		}
	}

	// Phase 3 — full status, post-heal (phase 1 covered the fetch).
	data, err := collectGitData(target.Path, false)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	// Pre-flight: collect every blocker, report once, publish nothing.
	pf := landPreflight(proj, target, base, data, *allowPinRewind, pre, basePre)
	out.Warnings = append(out.Warnings, pf.Warnings...)
	if len(pf.Blockers) > 0 {
		out.Blockers = pf.Blockers
		out.Reasons = append(out.Reasons, pf.Reasons...)
		out.Hint = pf.Hint
		return finishLand(out)
	}
	baseHeadBefore, err := runGit(base.Path, "rev-parse", "HEAD")
	if err != nil {
		out.Reasons = append(out.Reasons, fmt.Sprintf("cannot resolve %s HEAD: %v", base.Name, err))
		return finishLand(out)
	}

	// Push submodules first, then the feature branch: the base commit about to
	// be published references those submodule commits.
	pushed, skipped, failed := pushSubmodules(target.Path, data.Submodules)
	out.Pushed, out.Skipped, out.Failed = pushed, skipped, failed
	if len(failed) == 0 {
		branchResult := pushWorktreeBranch(target.Path, target.Branch)
		if branchResult.Status == "failed" {
			out.Failed = append(out.Failed, branchResult)
		} else {
			out.Pushed = append(out.Pushed, branchResult)
		}
	}
	deleteCache(target.Path, "git.json")
	if len(out.Failed) > 0 {
		out.Hint = fmt.Sprintf("integrate the rejected repo(s), then re-run: glittering worktree land --path %s", target.Path)
		return finishLand(out)
	}

	// Fast-forward the base worktree onto the feature branch and publish it.
	out.Base = landBaseWorktree(out.Base, target.Branch, baseHeadBefore)
	out.Landed = out.Base.Action != "failed"
	if !out.Landed {
		return finishLand(out)
	}
	if !syncResultsOK(out.Base.Submodules) {
		out.Warnings = append(out.Warnings, fmt.Sprintf(
			"base worktree %s: submodule pins did not converge — run: glittering git sync --path %s", base.Name, base.Path))
	}
	if !out.Base.Pushed {
		out.Hint = fmt.Sprintf("%s was fast-forwarded locally but not pushed; push it with: glittering git push --path %s", base.Branch, base.Path)
		return finishLand(out)
	}

	out.Success = true
	out.Hint = fmt.Sprintf("glittering worktree prune --path %s", proj.ProjectDir)
	return finishLand(out)
}

// finishLand emits the output and maps it to an exit code. Unlike `worktree
// remove`, a refusal is a failure: the caller asked for work to be landed and
// it was not.
func finishLand(out WorktreeLandOutput) int {
	// Empty lists, never null — callers index into these.
	for _, list := range []*[]PushRepoResult{&out.Pushed, &out.Skipped, &out.Failed} {
		if *list == nil {
			*list = []PushRepoResult{}
		}
	}
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

// pushWorktreeBranch pushes the feature branch itself. `git push`'s parent step
// is upstream-gated, but a freshly created worktree branch has no upstream yet,
// so the remote and ref are named explicitly.
func pushWorktreeBranch(wtPath, branch string) PushRepoResult {
	ref, _ := runGit(wtPath, "rev-parse", "HEAD")
	progressf("  pushing %s...\n", branch)
	if _, err := runGitNet(wtPath, "push", "--set-upstream", "origin", branch); err != nil {
		return PushRepoResult{Path: ".", Status: "failed", Ref: ref, Error: fmt.Sprintf("%v", err)}
	}
	return PushRepoResult{Path: ".", Status: "pushed", Ref: ref}
}

// landBaseWorktree fast-forwards the base worktree onto the feature branch,
// reconverges its submodule pins (the fast-forward moves gitlinks, and the base
// clones need the commits just pushed), then publishes the base branch.
// expectedHead guards the window between pre-flight and here: if another land
// moved the base branch, refuse rather than merge.
func landBaseWorktree(res WorktreeBaseResult, featureBranch, expectedHead string) WorktreeBaseResult {
	res.FromRef = expectedHead
	head, err := runGit(res.Path, "rev-parse", "HEAD")
	if err != nil {
		res.Action, res.Error = "failed", fmt.Sprintf("cannot resolve HEAD: %v", err)
		return res
	}
	if head != expectedHead {
		res.Action = "failed"
		res.Error = fmt.Sprintf("%s moved during land (%s → %s) — run `glittering worktree update` and re-run land",
			res.Branch, shortRef(expectedHead), shortRef(head))
		return res
	}
	progressf("  fast-forwarding %s to %s...\n", res.Branch, featureBranch)
	if _, err := runGit(res.Path, "merge", "--ff-only", featureBranch); err != nil {
		res.Action, res.Error = "failed", fmt.Sprintf("fast-forward of %s to %s failed: %v", res.Branch, featureBranch, err)
		return res
	}
	newHead, _ := runGit(res.Path, "rev-parse", "HEAD")
	res.ToRef = newHead
	res.NewCommits = countCommits(res.Path, expectedHead, newHead)
	res.Action = "fast_forwarded"
	if newHead == expectedHead {
		res.Action = "up_to_date"
	}

	// Converge pins before anything reads the base tree: an unconverged gitlink
	// leaves the base worktree dirty, which blocks the next update or land.
	// Folded with the pre-flight heal so neither pass erases the other.
	if sync, syncErr := syncSubmodules(res.Path, true, nil); syncErr == nil {
		res.Submodules = mergeSyncResults(res.Submodules, sync.Results)
	}
	deleteCache(res.Path, "git.json")

	progressf("  pushing %s...\n", res.Branch)
	if _, err := runGitNet(res.Path, "push", "--set-upstream", "origin", res.Branch); err != nil {
		res.Error = fmt.Sprintf("push of %s failed: %v", res.Branch, err)
		return res
	}
	res.Pushed = true
	return res
}
