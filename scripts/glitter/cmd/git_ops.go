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
	all := fs.Bool("all", false, "stage all changes (including untracked) before committing")
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
		logf("hint: commit-sub is deprecated, use: glittering git commit %s -m \"msg\" --path %s\n", subPath, root)
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
	all := fs.Bool("all", false, "stage all parent changes (including untracked) before committing")
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

// getOutOfSyncSubmodules returns submodule paths where HEAD differs from the parent's recorded ref.
func getOutOfSyncSubmodules(root string) ([]string, error) {
	paths, err := getSubmodulePaths(root)
	if err != nil {
		return nil, err
	}
	var outOfSync []string
	for _, subPath := range paths {
		subDir := filepath.Join(root, subPath)
		head, err := runGit(subDir, "rev-parse", "HEAD")
		if err != nil {
			continue
		}
		parentRef, err := runGit(root, "ls-tree", "HEAD", subPath)
		if err != nil || parentRef == "" {
			continue
		}
		fields := strings.Fields(parentRef)
		if len(fields) >= 3 && fields[2] != head {
			outOfSync = append(outOfSync, subPath)
		}
	}
	return outOfSync, nil
}

// commitParentRefs verifies sub HEADs are on remote, stages refs, commits and pushes parent.
// Returns GitCommitResult with Path=".".
func commitParentRefs(root string, subs []string, message string) GitCommitResult {
	// Fetch + verify each sub HEAD on remote
	for _, sub := range subs {
		subDir := filepath.Join(root, sub)

		if _, err := runGit(subDir, "fetch", "origin"); err != nil {
			return GitCommitResult{Path: ".", Error: fmt.Sprintf("fetch failed for %s: %v", sub, err)}
		}

		head, err := runGit(subDir, "rev-parse", "HEAD")
		if err != nil {
			return GitCommitResult{Path: ".", Error: fmt.Sprintf("cannot get HEAD for %s: %v", sub, err)}
		}

		branches, err := runGit(subDir, "branch", "-r", "--contains", head)
		if err != nil || strings.TrimSpace(branches) == "" {
			short := head
			if len(short) > 12 {
				short = short[:12]
			}
			return GitCommitResult{Path: ".", Error: fmt.Sprintf("%s HEAD %s is not pushed to remote", sub, short)}
		}
	}

	// Stage each sub ref
	var staged []string
	for _, sub := range subs {
		if _, err := runGit(root, "add", sub); err != nil {
			return GitCommitResult{Path: ".", Error: fmt.Sprintf("stage failed for %s: %v", sub, err)}
		}
		staged = append(staged, sub)
	}

	// Detect unstaged parent files (not part of submodule refs being committed)
	var unstaged []string
	if statusOut, err := runGit(root, "status", "--porcelain"); err == nil {
		subSet := make(map[string]bool, len(subs))
		for _, s := range subs {
			subSet[s] = true
		}
		for _, line := range strings.Split(statusOut, "\n") {
			if len(line) < 4 {
				continue
			}
			// porcelain format: XY <path> — skip files already staged (X != ' ' and X != '?')
			// We want files that are modified/untracked but NOT being staged as submodule refs
			xy := line[:2]
			filePath := strings.TrimSpace(line[3:])
			if subSet[filePath] {
				continue
			}
			// Unstaged modifications (Y column) or untracked (??)
			if xy[1] != ' ' || xy == "??" {
				unstaged = append(unstaged, filePath)
			}
		}
	}

	// Auto-generate message if empty
	if message == "" {
		names := make([]string, len(subs))
		for i, s := range subs {
			names[i] = filepath.Base(s)
		}
		if len(subs) == 1 {
			message = fmt.Sprintf("update %s submodule ref", names[0])
		} else {
			message = fmt.Sprintf("update %s submodule refs", strings.Join(names, ", "))
		}
	}

	// Commit
	if _, err := runGit(root, "commit", "-m", message); err != nil {
		return GitCommitResult{Path: ".", Error: fmt.Sprintf("commit failed: %v", err)}
	}

	ref, _ := runGit(root, "rev-parse", "HEAD")

	// Push
	_, pushErr := runGit(root, "push")
	pushed := pushErr == nil

	result := GitCommitResult{
		Path:    ".",
		Success: true,
		Ref:     ref,
		Staged:  staged,
		Pushed:  pushed,
	}
	if len(unstaged) > 0 {
		w := fmt.Sprintf("parent has %d unstaged file(s) (%s) — use -f to include them",
			len(unstaged), strings.Join(unstaged, ", "))
		result.Warning = w
		logf("warning: %s\n", w)
	}
	if !pushed {
		result.Error = fmt.Sprintf("push failed: %v", pushErr)
	}
	return result
}

// GitCommit is the unified commit command: commits submodules and auto-updates parent ref.
func GitCommit(args []string) int {
	fs := flag.NewFlagSet("git commit", flag.ExitOnError)
	fs.Usage = func() {
		logf("Usage: glittering git commit <sub>... -m \"msg\" [flags]\n\n")
		logf("Commit submodules and auto-update parent ref.\n\n")
		fs.PrintDefaults()
	}
	path := fs.String("path", ".", "repository root path")
	message := fs.StringP("message", "m", "", "commit message (required for sub commits)")
	all := fs.Bool("all", false, "stage all changes (including untracked) before committing")
	files := fs.StringArrayP("files", "f", nil, "specific files to stage (relative to submodule root)")
	staged := fs.Bool("staged", false, "commit whatever is already staged (skip staging)")
	noParent := fs.Bool("no-parent", false, "skip parent ref update")
	parentOnly := fs.Bool("parent-only", false, "parent-only mode: no sub commits, stage out-of-sync refs")
	parentMessage := fs.String("parent-message", "", "custom parent commit message (default: auto-generated)")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	// Expand comma-separated --files values
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

	// Validation
	if *noParent && *parentOnly {
		logf("error: --no-parent and --parent-only are mutually exclusive\n")
		return ExitUsage
	}
	// Staging flags mutual exclusivity
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

	hasStagingFlag := *all || len(*files) > 0 || *staged

	if *parentOnly && hasStagingFlag && *message == "" {
		logf("error: --message/-m is required when using staging flags with --parent-only\n")
		return ExitUsage
	}

	subs := fs.Args()

	if *parentOnly && hasStagingFlag && len(subs) > 0 {
		logf("error: submodule arguments cannot be used with --parent-only and staging flags\n")
		return ExitUsage
	}

	if !*parentOnly && len(subs) == 0 {
		logf("error: submodule path(s) required (or use --parent-only)\n")
		return ExitUsage
	}
	if !*parentOnly && *message == "" {
		logf("error: --message/-m is required\n")
		return ExitUsage
	}
	if len(*files) > 0 && len(subs) > 1 {
		logf("error: --files cannot be used with multiple submodules\n")
		return ExitUsage
	}

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Parent-only mode
	if *parentOnly {
		// Parent-only with staging flags: commit arbitrary parent files
		if hasStagingFlag {
			var stagedFiles []string

			if *all {
				if _, err := runGit(root, "add", "-A"); err != nil {
					output := GitCommitOutput{Path: root, Error: fmt.Sprintf("stage failed: %v", err)}
					outputJSON(output)
					return ExitFailure
				}

				// Warn if submodule refs are being staged (bypasses remote-push verification)
				subPaths, _ := getSubmodulePaths(root)
				if len(subPaths) > 0 {
					stagedNames, err := runGit(root, "diff", "--cached", "--name-only")
					if err == nil && stagedNames != "" {
						subSet := make(map[string]bool, len(subPaths))
						for _, sp := range subPaths {
							subSet[sp] = true
						}
						var warnSubs []string
						for _, name := range strings.Split(stagedNames, "\n") {
							name = strings.TrimSpace(name)
							if subSet[name] {
								warnSubs = append(warnSubs, name)
							}
						}
						if len(warnSubs) > 0 {
							progressf("glittering: WARNING: --all is staging submodule ref changes (%s) without verifying they are pushed to remote\n",
								strings.Join(warnSubs, ", "))
						}
					}
				}
			} else if len(*files) > 0 {
				for _, f := range *files {
					if _, err := runGit(root, "add", "--", f); err != nil {
						output := GitCommitOutput{Path: root, Error: fmt.Sprintf("stage failed for %s: %v", f, err)}
						outputJSON(output)
						return ExitFailure
					}
					stagedFiles = append(stagedFiles, f)
				}
			}
			// --staged: no staging action needed (commit index as-is)

			if _, err := runGit(root, "commit", "-m", *message); err != nil {
				parentResult := GitCommitResult{Path: ".", Error: fmt.Sprintf("commit failed: %v", err)}
				output := GitCommitOutput{Path: root, Parent: &parentResult, Submodules: []GitCommitResult{}, Error: parentResult.Error}
				outputJSON(output)
				return ExitFailure
			}

			ref, _ := runGit(root, "rev-parse", "HEAD")

			_, pushErr := runGit(root, "push")
			pushed := pushErr == nil

			parentResult := GitCommitResult{
				Path:    ".",
				Success: true,
				Ref:     ref,
				Staged:  stagedFiles,
				Pushed:  pushed,
			}
			if !pushed {
				parentResult.Error = fmt.Sprintf("push failed: %v", pushErr)
			}

			output := GitCommitOutput{
				Path:       root,
				Success:    parentResult.Success && pushed,
				Submodules: []GitCommitResult{},
				Parent:     &parentResult,
			}
			if !output.Success {
				output.Error = parentResult.Error
			}

			deleteCache(root, "git.json")
			outputJSON(output)

			if !output.Success {
				return ExitFailure
			}
			return ExitOK
		}

		// Parent-only without staging flags: auto-detect out-of-sync refs
		var targetSubs []string
		if len(subs) > 0 {
			for _, sub := range subs {
				resolved, resolveErr := resolveSubmodulePath(root, sub)
				if resolveErr != nil {
					logf("error: %v\n", resolveErr)
					return ExitUsage
				}
				targetSubs = append(targetSubs, resolved)
			}
		} else {
			targetSubs, err = getOutOfSyncSubmodules(root)
			if err != nil {
				output := GitCommitOutput{Path: root, Error: fmt.Sprintf("failed to detect out-of-sync submodules: %v", err)}
				outputJSON(output)
				return ExitFailure
			}
		}

		if len(targetSubs) == 0 {
			output := GitCommitOutput{Path: root, Success: true, Submodules: []GitCommitResult{}}
			progressf("glittering: nothing to do — all submodule refs are in sync\n")
			outputJSON(output)
			return ExitOK
		}

		parentMsg := *message
		if parentMsg == "" {
			parentMsg = *parentMessage
		}

		parentResult := commitParentRefs(root, targetSubs, parentMsg)
		output := GitCommitOutput{
			Path:       root,
			Success:    parentResult.Success && parentResult.Pushed,
			Submodules: []GitCommitResult{},
			Parent:     &parentResult,
		}
		if !output.Success {
			output.Error = parentResult.Error
		}

		deleteCache(root, "git.json")
		outputJSON(output)

		if !output.Success {
			return ExitFailure
		}
		return ExitOK
	}

	// Default mode: commit subs, then optionally parent
	resolvedSubs := make([]string, len(subs))
	for i, sub := range subs {
		resolved, resolveErr := resolveSubmodulePath(root, sub)
		if resolveErr != nil {
			logf("error: %v\n", resolveErr)
			return ExitUsage
		}
		resolvedSubs[i] = resolved
	}

	var subResults []GitCommitResult

	for i, subPath := range resolvedSubs {
		subDir := filepath.Join(root, subPath)

		// Stage
		if *all {
			if _, err := runGit(subDir, "add", "-A"); err != nil {
				subResults = append(subResults, GitCommitResult{Path: subPath, Error: fmt.Sprintf("stage failed: %v", err)})
				output := GitCommitOutput{Path: root, Submodules: subResults, Error: fmt.Sprintf("stage failed in %s: %v", subPath, err)}
				outputJSON(output)
				return ExitFailure
			}
		} else if len(*files) > 0 && i == 0 {
			for _, f := range *files {
				if _, err := runGit(subDir, "add", "--", f); err != nil {
					subResults = append(subResults, GitCommitResult{Path: subPath, Error: fmt.Sprintf("stage failed for %s: %v", f, err)})
					output := GitCommitOutput{Path: root, Submodules: subResults, Error: fmt.Sprintf("stage failed for %s in %s: %v", f, subPath, err)}
					outputJSON(output)
					return ExitFailure
				}
			}
		}

		// Commit
		if _, err := runGit(subDir, "commit", "-m", *message); err != nil {
			subResults = append(subResults, GitCommitResult{Path: subPath, Error: fmt.Sprintf("commit failed: %v", err)})
			output := GitCommitOutput{Path: root, Submodules: subResults, Error: fmt.Sprintf("commit failed in %s: %v", subPath, err)}
			outputJSON(output)
			return ExitFailure
		}

		ref, _ := runGit(subDir, "rev-parse", "HEAD")

		// Push
		_, pushErr := runGit(subDir, "push", "--set-upstream", "origin", "HEAD")
		pushed := pushErr == nil

		result := GitCommitResult{
			Path:    subPath,
			Success: true,
			Ref:     ref,
			Pushed:  pushed,
		}
		if !pushed {
			result.Error = fmt.Sprintf("push failed: %v", pushErr)
			subResults = append(subResults, result)
			output := GitCommitOutput{Path: root, Submodules: subResults, Error: result.Error}
			outputJSON(output)
			return ExitFailure
		}

		subResults = append(subResults, result)
	}

	// All subs succeeded
	output := GitCommitOutput{
		Path:       root,
		Success:    true,
		Submodules: subResults,
	}

	if *noParent {
		deleteCache(root, "git.json")
		outputJSON(output)
		logf("hint: update parent ref later: glittering git commit --parent-only --path %s\n", root)
		return ExitOK
	}

	// Auto-commit parent
	parentResult := commitParentRefs(root, resolvedSubs, *parentMessage)
	output.Parent = &parentResult

	if !parentResult.Success || !parentResult.Pushed {
		output.Success = false
		output.Error = parentResult.Error
	}

	deleteCache(root, "git.json")
	outputJSON(output)

	if !output.Success {
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
