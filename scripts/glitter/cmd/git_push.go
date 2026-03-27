package cmd

import (
	flag "github.com/spf13/pflag"
	"fmt"
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

	// Always fetch first to get accurate ahead/behind counts
	data, err := collectGitData(root, true)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	filters := parseFilter(*filter)
	if len(filters) > 0 {
		data.Submodules = filterGitSubmodules(data.Submodules, filters)
	}

	// Pre-flight: abort if any repo is dirty or any submodule is detached
	var preflight []string
	if data.Repo.Dirty {
		preflight = append(preflight, "parent repo has uncommitted changes")
	}
	for _, sub := range data.Submodules {
		if sub.Dirty {
			preflight = append(preflight, fmt.Sprintf("%s has uncommitted changes", sub.Path))
		}
		if sub.Detached {
			preflight = append(preflight, fmt.Sprintf("%s is in detached HEAD state", sub.Path))
		}
	}
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

	var pushed, skipped, failed []PushRepoResult

	// Push submodules first (so parent can reference pushed refs)
	for _, sub := range data.Submodules {
		if sub.AheadRemote == 0 || sub.Upstream == "" || sub.Branch == "" {
			if sub.AheadRemote > 0 && sub.Upstream == "" {
				skipped = append(skipped, PushRepoResult{Path: sub.Path, Status: "skipped", Error: "no upstream configured"})
			} else {
				skipped = append(skipped, PushRepoResult{Path: sub.Path, Status: "skipped"})
			}
			continue
		}
		subDir := filepath.Join(root, sub.Path)
		progressf("  pushing %s...\n", sub.Path)
		if _, pushErr := runGit(subDir, "push"); pushErr != nil {
			failed = append(failed, PushRepoResult{Path: sub.Path, Status: "failed", Ref: sub.Ref, Error: fmt.Sprintf("%v", pushErr)})
		} else {
			pushed = append(pushed, PushRepoResult{Path: sub.Path, Status: "pushed", Ref: sub.Ref})
		}
	}

	// Push parent (skip when filter is active)
	if len(filters) == 0 {
		if data.Repo.AheadRemote > 0 && data.Repo.Upstream != "" {
			progressf("  pushing parent...\n")
			if _, pushErr := runGit(root, "push"); pushErr != nil {
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
