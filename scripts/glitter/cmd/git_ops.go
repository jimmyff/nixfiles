package cmd

import (
	flag "github.com/spf13/pflag"
	"fmt"
	"path/filepath"
	"strings"
)

// GitCommitSub commits and pushes a single submodule.
func GitCommitSub(args []string) int {
	fs := flag.NewFlagSet("git commit-sub", flag.ExitOnError)
	fs.Usage = func() {
		logf("Usage: glittering git commit-sub <submodule> [flags]\n\n")
		logf("Example: glittering git commit-sub notes -m \"fix bug\" -f file1.dart -f file2.dart\n\n")
		fs.PrintDefaults()
	}
	path := fs.String("path", ".", "repository root path")
	message := fs.StringP("message", "m", "", "commit message (required)")
	all := fs.Bool("all", false, "stage all tracked changes before committing")
	files := fs.StringArrayP("files", "f", nil, "specific files to stage (relative to submodule root)")
	staged := fs.Bool("staged", false, "commit whatever is already staged (skip staging)")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	// Expand comma-separated --files values (accept both -f a -f b and -f "a,b")
	if len(*files) > 0 {
		var expanded []string
		for _, f := range *files {
			for _, part := range strings.Split(f, ",") {
				part = strings.TrimSpace(part)
				if part != "" {
					expanded = append(expanded, part)
				}
			}
		}
		*files = expanded
	}

	if *message == "" {
		logf("error: --message/-m (commit message) is required\n")
		return ExitUsage
	}

	// Validate mutual exclusivity of staging flags
	flagCount := 0
	if *all {
		flagCount++
	}
	if len(*files) > 0 {
		flagCount++
	}
	if *staged {
		flagCount++
	}
	if flagCount > 1 {
		logf("error: --all, --files, and --staged are mutually exclusive\n")
		return ExitUsage
	}

	remaining := fs.Args()
	if len(remaining) == 0 {
		logf("error: submodule path is required\nUsage: glittering git commit-sub <submodule> -m \"msg\" [-f file ...]\n")
		return ExitUsage
	}
	subPath := remaining[0]

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	resolvedPath, resolveErr := resolveSubmodulePath(root, subPath)
	if resolveErr != nil {
		logf("error: %v\n", resolveErr)
		return ExitUsage
	}
	subPath = resolvedPath
	subDir := filepath.Join(root, subPath)

	// Stage based on flags
	if *all {
		if _, err := runGit(subDir, "add", "-A"); err != nil {
			result := GitCommitResult{Path: root, Error: fmt.Sprintf("stage failed: %v", err)}
			outputJSON(result)
			return ExitFailure
		}
	} else if len(*files) > 0 {
		for _, f := range *files {
			if _, err := runGit(subDir, "add", "--", f); err != nil {
				result := GitCommitResult{Path: root, Error: fmt.Sprintf("stage failed for %s: %v", f, err)}
				outputJSON(result)
				return ExitFailure
			}
		}
	}
	// --staged or no flag: no-op (commit index as-is)

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
	if result.Success {
		logf("hint: update parent ref: glittering git commit-parent --message \"update %s submodule ref\" --path %s %s\n",
			filepath.Base(subPath), root, subPath)
	}
	if !pushed {
		return ExitFailure
	}
	return ExitOK
}

// GitCommitParent verifies submodule refs are on remote, stages them, commits and pushes parent.
func GitCommitParent(args []string) int {
	fs := flag.NewFlagSet("git commit-parent", flag.ExitOnError)
	fs.Usage = func() {
		logf("Usage: glittering git commit-parent <sub>... [flags]\n\n")
		logf("Example: glittering git commit-parent notes editor -m \"update submodule refs\"\n\n")
		fs.PrintDefaults()
	}
	path := fs.String("path", ".", "repository root path")
	message := fs.StringP("message", "m", "", "commit message (required)")
	all := fs.Bool("all", false, "stage all tracked parent changes before committing")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	if *message == "" {
		logf("error: --message/-m (commit message) is required\n")
		return ExitUsage
	}

	rawSubs := fs.Args()
	if len(rawSubs) == 0 {
		logf("error: specify submodule paths to stage\nUsage: glittering git commit-parent <sub>... -m \"msg\"\n")
		return ExitUsage
	}

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Resolve each submodule path
	submodules := make([]string, len(rawSubs))
	copy(submodules, rawSubs)
	for i, sub := range submodules {
		resolved, resolveErr := resolveSubmodulePath(root, sub)
		if resolveErr != nil {
			logf("error: %v\n", resolveErr)
			return ExitUsage
		}
		submodules[i] = resolved
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

	// Stage all tracked parent changes if --all
	if *all {
		if _, err := runGit(root, "add", "-A"); err != nil {
			result := GitCommitResult{Path: root, Error: fmt.Sprintf("stage all failed: %v", err)}
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
	filter := fs.String("filter", "", "comma-separated submodule name filters")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
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
	progressf("glittering: pulling parent (%s)...\n", branch)
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
		progressf("glittering: initialising %d new submodules...\n", len(uninit))
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

	// Filter submodules for pull (parent pull always runs)
	filters := parseFilter(*filter)
	submodulePaths = filterSubmodulePaths(submodulePaths, filters)

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
			progressf("  %s: skipped (dirty)\n", subPath)
			subResults = append(subResults, sub)
			continue
		}

		// Determine branch
		subBranch := getSubmoduleBranch(root, subPath)
		sub.Branch = subBranch

		// Checkout branch (get off detached HEAD)
		progressf("  %s: checkout %s, pulling...\n", subPath, subBranch)
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

		progressf("  %s: %d new commits\n", subPath, sub.NewCommits)
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
