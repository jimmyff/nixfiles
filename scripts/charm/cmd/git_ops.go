package cmd

import (
	"flag"
	"fmt"
	"path/filepath"
	"strings"
)

// GitCommitSub commits and pushes a single submodule.
func GitCommitSub(args []string) int {
	fs := flag.NewFlagSet("git commit-sub", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	message := fs.String("m", "", "commit message (required)")
	all := fs.Bool("all", false, "stage all tracked changes before committing")
	fs.Parse(args)

	if *message == "" {
		logf("error: -m (commit message) is required\n")
		return ExitUsage
	}

	remaining := fs.Args()
	if len(remaining) == 0 {
		logf("error: submodule path is required\n")
		return ExitUsage
	}
	subPath := remaining[0]

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	subDir := filepath.Join(root, subPath)

	// Stage if --all
	if *all {
		if _, err := runGit(subDir, "add", "-A"); err != nil {
			result := GitCommitResult{Path: root, Error: fmt.Sprintf("stage failed: %v", err)}
			outputJSON(result)
			return ExitFailure
		}
	}

	// Commit
	if _, err := runGit(subDir, "commit", "-m", *message); err != nil {
		result := GitCommitResult{Path: root, Error: fmt.Sprintf("commit failed: %v", err)}
		outputJSON(result)
		return ExitFailure
	}

	// Get new ref
	ref, _ := runGit(subDir, "rev-parse", "HEAD")

	// Push
	_, pushErr := runGit(subDir, "push", "--set-upstream", "origin", "HEAD")
	pushed := pushErr == nil

	result := GitCommitResult{
		Path:    root,
		Success: true,
		Ref:     ref,
		Pushed:  pushed,
	}
	if !pushed {
		result.Error = fmt.Sprintf("push failed: %v", pushErr)
	}

	deleteCache(root, "git.json")

	outputJSON(result)
	if !pushed {
		return ExitFailure
	}
	return ExitOK
}

// GitCommitParent verifies submodule refs are on remote, stages them, commits and pushes parent.
func GitCommitParent(args []string) int {
	fs := flag.NewFlagSet("git commit-parent", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	message := fs.String("m", "", "commit message (required)")
	fs.Parse(args)

	if *message == "" {
		logf("error: -m (commit message) is required\n")
		return ExitUsage
	}

	submodules := fs.Args()
	if len(submodules) == 0 {
		logf("error: specify submodule paths to stage\n")
		return ExitUsage
	}

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Verify each submodule's HEAD exists on its remote
	for _, sub := range submodules {
		subDir := filepath.Join(root, sub)

		// Fetch latest from remote
		if _, err := runGit(subDir, "fetch", "origin"); err != nil {
			result := GitCommitResult{Path: root, Error: fmt.Sprintf("fetch failed for %s: %v", sub, err)}
			outputJSON(result)
			return ExitFailure
		}

		// Get HEAD
		head, err := runGit(subDir, "rev-parse", "HEAD")
		if err != nil {
			result := GitCommitResult{Path: root, Error: fmt.Sprintf("cannot get HEAD for %s: %v", sub, err)}
			outputJSON(result)
			return ExitFailure
		}

		// Check if HEAD is on any remote branch
		branches, err := runGit(subDir, "branch", "-r", "--contains", head)
		if err != nil || strings.TrimSpace(branches) == "" {
			result := GitCommitResult{Path: root, Error: fmt.Sprintf("%s HEAD %s is not pushed to remote", sub, head[:12])}
			outputJSON(result)
			return ExitFailure
		}
	}

	// Stage submodule refs
	var staged []string
	for _, sub := range submodules {
		if _, err := runGit(root, "add", sub); err != nil {
			result := GitCommitResult{Path: root, Error: fmt.Sprintf("stage failed for %s: %v", sub, err)}
			outputJSON(result)
			return ExitFailure
		}
		staged = append(staged, sub)
	}

	// Commit
	if _, err := runGit(root, "commit", "-m", *message); err != nil {
		result := GitCommitResult{Path: root, Error: fmt.Sprintf("commit failed: %v", err)}
		outputJSON(result)
		return ExitFailure
	}

	ref, _ := runGit(root, "rev-parse", "HEAD")

	// Push
	_, pushErr := runGit(root, "push")
	pushed := pushErr == nil

	result := GitCommitResult{
		Path:    root,
		Success: true,
		Ref:     ref,
		Staged:  staged,
		Pushed:  pushed,
	}
	if !pushed {
		result.Error = fmt.Sprintf("push failed: %v", pushErr)
	}

	deleteCache(root, "git.json")

	outputJSON(result)
	if !pushed {
		return ExitFailure
	}
	return ExitOK
}

// GitPull pulls the parent repo, syncs submodule refs, then checks out and pulls each submodule.
func GitPull(args []string) int {
	fs := flag.NewFlagSet("git pull", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	var warnings []string

	// Pre-flight: check parent dirty/stash
	parentPorcelain, _ := runGit(root, "status", "--porcelain")
	if parentPorcelain != "" {
		warnings = append(warnings, "parent repo has uncommitted changes")
	}
	parentStash := getStashCount(root)
	if parentStash > 0 {
		warnings = append(warnings, fmt.Sprintf("parent repo has %d stash entries", parentStash))
	}

	// Detect parent branch
	branch, _ := runGit(root, "branch", "--show-current")
	if branch == "" {
		branch = "main"
	}

	// Pull parent
	logf("charm: pulling parent (%s)...\n", branch)
	_, pullErr := runGit(root, "pull", "origin", branch)
	if pullErr != nil {
		result := GitPullResult{Path: root, Branch: branch, Warnings: warnings, Error: fmt.Sprintf("pull failed: %v", pullErr)}
		outputJSON(result)
		return ExitFailure
	}

	// Init+clone any new submodules without resetting existing ones.
	// git submodule update --init resets ALL submodules to parent's recorded ref,
	// which is counterproductive when we're about to checkout+pull each one.
	// Instead, detect uninitialised submodules and only update those.
	uninit := getUninitialisedSubmodules(root)
	if len(uninit) > 0 {
		logf("charm: initialising %d new submodules...\n", len(uninit))
		args := append([]string{"submodule", "update", "--init", "--"}, uninit...)
		if _, initErr := runGit(root, args...); initErr != nil {
			warnings = append(warnings, fmt.Sprintf("submodule init failed: %v", initErr))
		}
	}

	// Get submodule paths
	submodulePaths, err := getSubmodulePaths(root)
	if err != nil {
		result := GitPullResult{Path: root, Branch: branch, Success: true, Warnings: warnings, Submodules: []GitPullSubmodule{}}
		outputJSON(result)
		return ExitOK
	}

	// Pre-flight: check each submodule for dirty state
	dirtySet := make(map[string]bool)
	for _, subPath := range submodulePaths {
		subDir := filepath.Join(root, subPath)
		porcelain, _ := runGit(subDir, "status", "--porcelain")
		if porcelain != "" {
			dirtySet[subPath] = true
			warnings = append(warnings, fmt.Sprintf("%s has uncommitted changes (skipping pull)", subPath))
		}
	}

	// Pull each submodule
	var subResults []GitPullSubmodule
	hasError := false
	for _, subPath := range submodulePaths {
		subDir := filepath.Join(root, subPath)
		sub := GitPullSubmodule{Path: subPath}

		// Skip dirty submodules
		if dirtySet[subPath] {
			sub.WasDirty = true
			sub.Branch = getSubmoduleBranch(root, subPath)
			logf("  %s: skipped (dirty)\n", subPath)
			subResults = append(subResults, sub)
			continue
		}

		// Determine branch
		subBranch := getSubmoduleBranch(root, subPath)
		sub.Branch = subBranch

		// Checkout branch (get off detached HEAD)
		logf("  %s: checkout %s, pulling...\n", subPath, subBranch)
		if _, err := runGit(subDir, "checkout", subBranch); err != nil {
			sub.Error = fmt.Sprintf("checkout %s failed: %v", subBranch, err)
			hasError = true
			subResults = append(subResults, sub)
			continue
		}

		// Get before-ref (after checkout, so we only count commits from pull)
		beforeRef, _ := runGit(subDir, "rev-parse", "HEAD")

		// Pull
		if _, err := runGit(subDir, "pull", "origin", subBranch); err != nil {
			sub.Error = fmt.Sprintf("pull failed: %v", err)
			hasError = true
			subResults = append(subResults, sub)
			continue
		}

		// Count new commits
		afterRef, _ := runGit(subDir, "rev-parse", "HEAD")
		if beforeRef != "" && afterRef != "" && beforeRef != afterRef {
			countStr, err := runGit(subDir, "rev-list", "--count", fmt.Sprintf("%s..%s", beforeRef, afterRef))
			if err == nil {
				count := 0
				fmt.Sscanf(countStr, "%d", &count)
				sub.NewCommits = count
			}
		}

		logf("  %s: %d new commits\n", subPath, sub.NewCommits)
		subResults = append(subResults, sub)
	}

	result := GitPullResult{
		Path:       root,
		Success:    !hasError,
		Branch:     branch,
		Submodules: subResults,
		Warnings:   warnings,
	}
	if result.Submodules == nil {
		result.Submodules = []GitPullSubmodule{}
	}
	if result.Warnings == nil {
		result.Warnings = []string{}
	}

	// Invalidate git cache since repo state has changed
	deleteCache(root, "git.json")

	outputJSON(result)
	if hasError {
		return ExitFailure
	}
	return ExitOK
}
