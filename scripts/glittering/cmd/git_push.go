package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"path/filepath"
)

// GitPush pushes all repos that have unpushed commits.
func GitPush(args []string) int {
	fs := flag.NewFlagSet("git push", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	filter := fs.String("filter", "", "comma-separated submodule name filters")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Reject "." before the network fetch — filtered push operates on
	// submodules only; include the parent by running without --filter.
	filters := parseFilter(*filter)
	if includeParent, _ := splitParentFilter(filters); includeParent {
		logf("error: --filter . is not supported for git push — \".\" is the parent repo, and filtered push operates on submodules only; run without --filter to include the parent\n")
		return ExitUsage
	}

	// Always fetch first to get accurate ahead/behind counts
	data, err := collectGitData(root, true)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	if len(filters) > 0 {
		warnUnmatchedFilters(filters, submodulePathsOf(data.Submodules), "submodule")
		data.Submodules = filterGitSubmodules(data.Submodules, filters)
	}

	// Pre-flight: abort if any repo is dirty or any submodule is detached.
	// Skip the parent dirty check when --filter is active — the parent isn't
	// pushed in that mode, so its dirty state is irrelevant.
	preflight := pushPreflightReasons(data, len(filters) == 0)
	if len(preflight) > 0 {
		out := PushOutput{
			Path:    root,
			Success: false,
			Pushed:  []PushRepoResult{},
			Skipped: []PushRepoResult{},
			Failed:  []PushRepoResult{},
			Error:   fmt.Sprintf("pre-flight failed: %s", preflight[0]),
		}
		outputJSON(out)
		return ExitFailure
	}

	// Push submodules first (so parent can reference pushed refs)
	pushed, skipped, failed := pushSubmodules(root, data.Submodules)

	// Push parent (skip when filter is active)
	if len(filters) == 0 {
		if data.Repo.AheadRemote > 0 && data.Repo.Upstream != "" {
			progressf("  pushing parent...\n")
			if _, pushErr := runGitNet(root, "push"); pushErr != nil {
				failed = append(failed, PushRepoResult{Path: ".", Status: "failed", Ref: data.Repo.Ref, Error: fmt.Sprintf("%v", pushErr)})
			} else {
				pushed = append(pushed, PushRepoResult{Path: ".", Status: "pushed", Ref: data.Repo.Ref})
			}
		} else if data.Repo.AheadRemote > 0 && data.Repo.Upstream == "" {
			skipped = append(skipped, PushRepoResult{Path: ".", Status: "skipped", Error: "no upstream configured"})
		} else {
			skipped = append(skipped, PushRepoResult{Path: ".", Status: "skipped"})
		}
	}

	// Invalidate git cache
	deleteCache(root, "git.json")

	out := PushOutput{
		Path:    root,
		Success: len(failed) == 0,
		Pushed:  pushed,
		Skipped: skipped,
		Failed:  failed,
	}
	if out.Pushed == nil {
		out.Pushed = []PushRepoResult{}
	}
	if out.Skipped == nil {
		out.Skipped = []PushRepoResult{}
	}
	if out.Failed == nil {
		out.Failed = []PushRepoResult{}
	}

	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	if len(failed) > 0 {
		return ExitFailure
	}
	return ExitOK
}

// pushPreflightReasons lists every reason a push should be refused: uncommitted
// changes or a detached HEAD anywhere in the tree. includeParent covers the
// parent repo (false when only submodules will be pushed). Callers decide
// whether to report the first reason (`git push`) or all of them
// (`worktree land`).
func pushPreflightReasons(data GitOutput, includeParent bool) []string {
	var reasons []string
	if includeParent && data.Repo.Dirty {
		reasons = append(reasons, "parent repo has uncommitted changes")
	}
	for _, sub := range data.Submodules {
		if sub.Dirty {
			reasons = append(reasons, fmt.Sprintf("%s has uncommitted changes", sub.Path))
		}
		if sub.Detached {
			reasons = append(reasons, fmt.Sprintf("%s is in detached HEAD state", sub.Path))
		}
	}
	return reasons
}

// pushSubmodules pushes every submodule with unpushed commits, in order, so a
// parent ref bump can only ever reference commits that are already on the
// remote. Shared by `git push` and `worktree land`.
func pushSubmodules(root string, subs []GitSubmoduleStatus) (pushed, skipped, failed []PushRepoResult) {
	for _, sub := range subs {
		if sub.AheadRemote == 0 || sub.Upstream == "" || sub.Branch == "" {
			if sub.AheadRemote > 0 && sub.Upstream == "" {
				skipped = append(skipped, PushRepoResult{Path: sub.Path, Status: "skipped", Error: "no upstream configured"})
			} else {
				skipped = append(skipped, PushRepoResult{Path: sub.Path, Status: "skipped"})
			}
			continue
		}
		progressf("  pushing %s...\n", sub.Path)
		if _, pushErr := runGitNet(filepath.Join(root, sub.Path), "push"); pushErr != nil {
			failed = append(failed, PushRepoResult{Path: sub.Path, Status: "failed", Ref: sub.Ref, Error: fmt.Sprintf("%v", pushErr)})
		} else {
			pushed = append(pushed, PushRepoResult{Path: sub.Path, Status: "pushed", Ref: sub.Ref})
		}
	}
	return pushed, skipped, failed
}
