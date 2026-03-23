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
			result := GitCommitResult{Error: fmt.Sprintf("stage failed: %v", err)}
			outputJSON(result)
			return ExitFailure
		}
	}

	// Commit
	if _, err := runGit(subDir, "commit", "-m", *message); err != nil {
		result := GitCommitResult{Error: fmt.Sprintf("commit failed: %v", err)}
		outputJSON(result)
		return ExitFailure
	}

	// Get new ref
	ref, _ := runGit(subDir, "rev-parse", "HEAD")

	// Push
	_, pushErr := runGit(subDir, "push", "--set-upstream", "origin", "HEAD")
	pushed := pushErr == nil

	result := GitCommitResult{
		Success: true,
		Ref:     ref,
		Pushed:  pushed,
	}
	if !pushed {
		result.Error = fmt.Sprintf("push failed: %v", pushErr)
	}

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
			result := GitCommitResult{Error: fmt.Sprintf("fetch failed for %s: %v", sub, err)}
			outputJSON(result)
			return ExitFailure
		}

		// Get HEAD
		head, err := runGit(subDir, "rev-parse", "HEAD")
		if err != nil {
			result := GitCommitResult{Error: fmt.Sprintf("cannot get HEAD for %s: %v", sub, err)}
			outputJSON(result)
			return ExitFailure
		}

		// Check if HEAD is on any remote branch
		branches, err := runGit(subDir, "branch", "-r", "--contains", head)
		if err != nil || strings.TrimSpace(branches) == "" {
			result := GitCommitResult{Error: fmt.Sprintf("%s HEAD %s is not pushed to remote", sub, head[:12])}
			outputJSON(result)
			return ExitFailure
		}
	}

	// Stage submodule refs
	var staged []string
	for _, sub := range submodules {
		if _, err := runGit(root, "add", sub); err != nil {
			result := GitCommitResult{Error: fmt.Sprintf("stage failed for %s: %v", sub, err)}
			outputJSON(result)
			return ExitFailure
		}
		staged = append(staged, sub)
	}

	// Commit
	if _, err := runGit(root, "commit", "-m", *message); err != nil {
		result := GitCommitResult{Error: fmt.Sprintf("commit failed: %v", err)}
		outputJSON(result)
		return ExitFailure
	}

	ref, _ := runGit(root, "rev-parse", "HEAD")

	// Push
	_, pushErr := runGit(root, "push")
	pushed := pushErr == nil

	result := GitCommitResult{
		Success: true,
		Ref:     ref,
		Staged:  staged,
		Pushed:  pushed,
	}
	if !pushed {
		result.Error = fmt.Sprintf("push failed: %v", pushErr)
	}

	outputJSON(result)
	if !pushed {
		return ExitFailure
	}
	return ExitOK
}

// GitPull pulls the parent repo and syncs submodules.
func GitPull(args []string) int {
	fs := flag.NewFlagSet("git pull", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	logf("charm: pulling %s\n", root)

	// Detect current branch, fall back to "main"
	branch, _ := runGit(root, "branch", "--show-current")
	if branch == "" {
		branch = "main"
	}

	// Pull parent
	_, pullErr := runGit(root, "pull", "origin", branch)
	if pullErr != nil {
		result := GitPullResult{Error: fmt.Sprintf("pull failed: %v", pullErr)}
		outputJSON(result)
		return ExitFailure
	}

	// Sync submodules
	_, subErr := runGit(root, "submodule", "update", "--init")
	synced := subErr == nil

	result := GitPullResult{
		Success:          true,
		SubmodulesSynced: synced,
	}
	if !synced {
		result.Error = fmt.Sprintf("submodule sync failed: %v", subErr)
	}

	outputJSON(result)
	if !synced {
		return ExitFailure
	}
	return ExitOK
}

// GitUpdate pulls latest in each submodule from its remote.
func GitUpdate(args []string) int {
	fs := flag.NewFlagSet("git update", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	submodulePaths, err := getSubmodulePaths(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	logf("charm: updating %d submodules\n", len(submodulePaths))

	var subResults []GitUpdateSubmodule
	hasError := false
	for _, subPath := range submodulePaths {
		subDir := filepath.Join(root, subPath)
		sub := GitUpdateSubmodule{Path: subPath}

		// Get current ref before pull
		beforeRef, _ := runGit(subDir, "rev-parse", "HEAD")

		// Detect current branch, fall back to "main"
		subBranch, _ := runGit(subDir, "branch", "--show-current")
		if subBranch == "" {
			subBranch = "main"
		}

		// Pull
		_, pullErr := runGit(subDir, "pull", "origin", subBranch)
		if pullErr != nil {
			sub.Error = fmt.Sprintf("pull failed: %v", pullErr)
			hasError = true
			logf("  %s: error\n", subPath)
		} else {
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
		}

		subResults = append(subResults, sub)
	}

	result := GitUpdateResult{
		Success:    !hasError,
		Submodules: subResults,
	}
	if result.Submodules == nil {
		result.Submodules = []GitUpdateSubmodule{}
	}

	outputJSON(result)
	if hasError {
		return ExitFailure
	}
	return ExitOK
}
