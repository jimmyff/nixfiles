package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"strings"
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
		Reasons:    []string{}, Warnings: []string{},
		Pushed: []PushRepoResult{}, Skipped: []PushRepoResult{}, Failed: []PushRepoResult{},
	}

	// Shape refusals: nothing to land, or nowhere to land it.
	base, hasBase := baseWorktree(metas, proj.BaseBranch)
	switch {
	case !hasBase:
		out.Reasons = append(out.Reasons, fmt.Sprintf(
			"no worktree on the base branch %q — land fast-forwards it, so it must be checked out", proj.BaseBranch))
	case base.Path == target.Path:
		out.Reasons = append(out.Reasons, "refusing to land the base worktree into itself")
	}
	if target.Branch == "" {
		out.Reasons = append(out.Reasons, "worktree is in detached HEAD state — nothing to land")
	}
	if len(out.Reasons) > 0 {
		return finishLand(out)
	}
	out.Base = WorktreeBaseResult{
		Name: base.Name, Path: base.Path, Branch: base.Branch,
		Action: "missing", Submodules: []GitSyncSubmodule{},
	}

	// Fetch + full status for the feature worktree (parent refs are shared, so
	// this also refreshes the base branch's remote-tracking ref).
	data, err := collectGitData(target.Path, true)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	// Pre-flight: collect every blocker, report once, touch nothing.
	reasons, warnings, hint := landPreflight(proj, target, base, data, *allowPinRewind)
	out.Warnings = append(out.Warnings, warnings...)
	if len(reasons) > 0 {
		out.Reasons = append(out.Reasons, reasons...)
		out.Hint = hint
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

// landPreflight collects every reason a land must be refused, so one run
// reports the full list instead of surfacing blockers one at a time. Pin
// regressions are demoted to warnings when allowPinRewind is set. hint is the
// concrete remedy for the first blocker that has one.
func landPreflight(proj projectInfo, target, base worktreeMeta, data GitOutput, allowPinRewind bool) (reasons, warnings []string, hint string) {
	reasons = pushPreflightReasons(data, true)

	// Containment: the base branch only ever moves to a commit that provably
	// contains it — local and remote alike.
	for _, ref := range baseRefs(proj.BaseBranch) {
		if _, err := runGit(target.Path, "rev-parse", "--verify", "--quiet", ref); err != nil {
			continue // no such ref yet — nothing to contain
		}
		if _, err := runGit(target.Path, "merge-base", "--is-ancestor", ref, "HEAD"); err != nil {
			reasons = append(reasons, fmt.Sprintf(
				"%s does not contain %s — run `glittering worktree update` first", target.Branch, strings.TrimPrefix(ref, "refs/")))
			if hint == "" {
				hint = fmt.Sprintf("glittering worktree update --path %s", target.Path)
			}
		}
	}

	// Containment covers the parent's history, not its gitlinks: a tree that
	// rewound a pin still fast-forwards, so check the pins themselves.
	for _, reg := range detectPinRegressions(target.Path, submodulePathsOf(data.Submodules), baseRefs(proj.BaseBranch)) {
		if allowPinRewind {
			warnings = append(warnings, "--allow-pin-rewind: "+reg.reason())
			continue
		}
		reasons = append(reasons, reg.reason()+" — pass --allow-pin-rewind if the revert is deliberate")
		if hint == "" {
			hint = reg.fix(target.Path)
		}
	}

	// Pushes that would be rejected, caught before anything is published.
	if data.Repo.AheadRemote > 0 && data.Repo.BehindRemote > 0 {
		reasons = append(reasons, fmt.Sprintf(
			"%s has diverged from %s (%d ahead / %d behind) — integrate it before landing",
			target.Branch, data.Repo.Upstream, data.Repo.AheadRemote, data.Repo.BehindRemote))
	}
	for _, sub := range data.Submodules {
		switch {
		case sub.AheadRemote > 0 && sub.BehindRemote > 0:
			reasons = append(reasons, fmt.Sprintf(
				"%s has diverged from %s (%d ahead / %d behind) — another worktree pushed the same submodule branch; merge %s in %s, bump the pin with `glittering git commit --parent-only --path %s`, then re-run",
				sub.Path, sub.Upstream, sub.AheadRemote, sub.BehindRemote, sub.Upstream, sub.Path, target.Path))
		case !sub.HeadOnRemote && (sub.Upstream == "" || sub.Branch == ""):
			reasons = append(reasons, fmt.Sprintf(
				"%s has commits that are on no remote and no upstream to push to — push it manually first", sub.Path))
		}
	}

	// The base worktree's branch is about to be fast-forwarded under it.
	if base.Branch != proj.BaseBranch {
		reasons = append(reasons, fmt.Sprintf("base worktree %s is not on %s", base.Name, proj.BaseBranch))
	}
	if entries, err := statusEntries(base.Path); err == nil && len(entries) > 0 {
		reasons = append(reasons, fmt.Sprintf(
			"base worktree %s has uncommitted changes (%s)", base.Name, strings.Join(entryPaths(entries, 10), ", ")))
	}
	return reasons, warnings, hint
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
	if sync, syncErr := syncSubmodules(res.Path, true, nil); syncErr == nil {
		res.Submodules = sync.Results
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
