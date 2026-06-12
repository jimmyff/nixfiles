package cmd

import (
	flag "github.com/spf13/pflag"
	"fmt"
	"path/filepath"
	"strings"
	"sync"
)

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

// parentFileClassification holds the results of classifying parent repo
// files from git status porcelain output.
type parentFileClassification struct {
	Staged   []string // non-submodule files already in the index
	Unstaged []string // non-submodule files with working-tree changes or untracked
}

// classifyParentFiles separates non-submodule status entries into staged
// (index-only — these ride along with the next commit) and unstaged
// (working-tree changes or untracked — these get left behind).
func classifyParentFiles(entries []porcelainEntry, submodulePaths []string) parentFileClassification {
	subSet := make(map[string]bool, len(submodulePaths))
	for _, s := range submodulePaths {
		subSet[s] = true
	}

	var result parentFileClassification
	for _, e := range entries {
		if subSet[e.Path] {
			continue
		}
		switch {
		case e.X == '?' && e.Y == '?':
			result.Unstaged = append(result.Unstaged, e.Path)
		case e.Y != ' ':
			result.Unstaged = append(result.Unstaged, e.Path)
		case e.X != ' ':
			result.Staged = append(result.Staged, e.Path)
		}
	}
	return result
}

// verifySubHeadOnRemote fetches origin and confirms the submodule's HEAD
// exists on a remote branch.
func verifySubHeadOnRemote(subDir, sub string) error {
	if _, err := runGitNet(subDir, "fetch", "origin"); err != nil {
		return fmt.Errorf("fetch failed for %s: %v", sub, err)
	}

	head, err := runGit(subDir, "rev-parse", "HEAD")
	if err != nil {
		return fmt.Errorf("cannot get HEAD for %s: %v", sub, err)
	}

	branches, err := runGit(subDir, "branch", "-r", "--contains", head)
	if err != nil || strings.TrimSpace(branches) == "" {
		short := head
		if len(short) > 12 {
			short = short[:12]
		}
		return fmt.Errorf("%s HEAD %s is not pushed to remote", sub, short)
	}
	return nil
}

// commitParentRefs verifies sub HEADs are on remote, stages refs (plus any
// explicitly requested parentFiles), commits and pushes parent.
// Returns GitCommitResult with Path=".".
func commitParentRefs(root string, subs []string, message string, parentFiles []string) GitCommitResult {
	// Fetch + verify each sub HEAD on remote — network-bound, so run in
	// parallel. Errors land in an indexed slice (race-free) and the first
	// failing sub is reported deterministically.
	const maxJobs = 8
	verifyErrs := make([]error, len(subs))
	sem := make(chan struct{}, maxJobs)
	var wg sync.WaitGroup
	for i, sub := range subs {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, sub string) {
			defer wg.Done()
			defer func() { <-sem }()
			verifyErrs[i] = verifySubHeadOnRemote(filepath.Join(root, sub), sub)
		}(i, sub)
	}
	wg.Wait()
	for _, err := range verifyErrs {
		if err != nil {
			return GitCommitResult{Path: ".", Error: err.Error()}
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

	// Stage explicitly requested parent files
	requested := make(map[string]bool, len(parentFiles))
	for _, f := range parentFiles {
		if _, err := runGit(root, "add", "--", f); err != nil {
			return GitCommitResult{Path: ".", Error: fmt.Sprintf("stage failed for parent file %s: %v", f, err)}
		}
		staged = append(staged, f)
		requested[f] = true
	}

	// Classify remaining parent files: staged ones ride along with this
	// commit; unstaged/untracked ones are left behind and must be reported —
	// a refs-only commit that silently omits dirty parent files reads as
	// "everything committed" when it isn't.
	var parentWarnings []string
	var leftUncommitted []string
	if entries, err := statusEntries(root); err == nil {
		classification := classifyParentFiles(entries, subs)
		if len(classification.Unstaged) > 0 {
			leftUncommitted = classification.Unstaged
			w := fmt.Sprintf("parent has %d file(s) NOT included in this commit (%s) — include them with --parent-files/-F, or commit separately with --parent-only -f",
				len(classification.Unstaged), strings.Join(classification.Unstaged, ", "))
			parentWarnings = append(parentWarnings, w)
			logf("warning: %s\n", w)
		}
		// Warn about pre-staged files riding along (excluding the ones the
		// caller just requested via --parent-files — those are intentional).
		var preStaged []string
		for _, f := range classification.Staged {
			if !requested[f] {
				preStaged = append(preStaged, f)
			}
		}
		if len(preStaged) > 0 {
			w := fmt.Sprintf("parent has %d previously staged file(s) that will be included in this commit: %s",
				len(preStaged), strings.Join(preStaged, ", "))
			parentWarnings = append(parentWarnings, w)
			logf("warning: %s\n", w)
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
	_, pushErr := runGitNet(root, "push")
	pushed := pushErr == nil

	result := GitCommitResult{
		Path:            ".",
		Success:         true,
		Ref:             ref,
		Staged:          staged,
		Pushed:          pushed,
		LeftUncommitted: leftUncommitted,
		Warnings:        parentWarnings,
	}
	if !pushed {
		result.Error = fmt.Sprintf("push failed: %v", pushErr)
	}
	return result
}

// recoveryHint returns guidance when some submodules were already
// committed+pushed but the run failed before the parent ref bump — without
// it, those refs silently stay stale in the parent.
func recoveryHint(subResults []GitCommitResult, root string) string {
	var done []string
	for _, r := range subResults {
		if r.Success && r.Pushed {
			done = append(done, r.Path)
		}
	}
	if len(done) == 0 {
		return ""
	}
	return fmt.Sprintf("%d submodule(s) already committed+pushed (%s); after fixing, bump parent refs with: glittering git commit --parent-only --path %s",
		len(done), strings.Join(done, ", "), root)
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
	all := fs.Bool("all", false, "stage all changes in each named submodule (parent repo files are NOT staged; see --parent-files)")
	files := fs.StringArrayP("files", "f", nil, "specific files to stage (relative to submodule root)")
	staged := fs.Bool("staged", false, "commit whatever is already staged (skip staging)")
	parentFiles := fs.StringArrayP("parent-files", "F", nil, "parent repo files to stage into the parent commit alongside the submodule ref bumps")
	noParent := fs.Bool("no-parent", false, "skip parent ref update")
	parentOnly := fs.Bool("parent-only", false, "parent-only mode: no sub commits, stage out-of-sync refs")
	parentMessage := fs.String("parent-message", "", "custom parent commit message (default: auto-generated)")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	// Accept both -f a -f b and -f "a,b"
	*files = expandCommaList(*files)
	*parentFiles = expandCommaList(*parentFiles)

	// Validation
	if *noParent && *parentOnly {
		logf("error: --no-parent and --parent-only are mutually exclusive\n")
		return ExitUsage
	}
	if *noParent && len(*parentFiles) > 0 {
		logf("error: --parent-files cannot be used with --no-parent (there is no parent commit to stage into)\n")
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

	if *parentOnly && hasStagingFlag && len(*parentFiles) > 0 {
		logf("error: --parent-files is redundant in --parent-only staging mode; use -f\n")
		return ExitUsage
	}

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

			// Empty-stage check: produce a clear error rather than letting git commit
			// fall through with "nothing to commit" on stdout.
			if _, diffErr := runGit(root, "diff", "--cached", "--quiet"); diffErr == nil {
				msg := "nothing staged in parent; pass --all, -f <file>, --staged, or stage manually first"
				parentResult := GitCommitResult{Path: ".", Error: msg}
				output := GitCommitOutput{Path: root, Parent: &parentResult, Submodules: []GitCommitResult{}, Error: msg}
				outputJSON(output)
				return ExitFailure
			}

			if _, err := runGit(root, "commit", "-m", *message); err != nil {
				parentResult := GitCommitResult{Path: ".", Error: fmt.Sprintf("commit failed: %v", err)}
				output := GitCommitOutput{Path: root, Parent: &parentResult, Submodules: []GitCommitResult{}, Error: parentResult.Error}
				outputJSON(output)
				return ExitFailure
			}

			ref, _ := runGit(root, "rev-parse", "HEAD")

			_, pushErr := runGitNet(root, "push")
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
			if len(*parentFiles) > 0 {
				logf("error: no submodule refs to update; commit parent files alone with --parent-only -f <file>\n")
				return ExitUsage
			}
			output := GitCommitOutput{Path: root, Success: true, Submodules: []GitCommitResult{}}
			progressf("glittering: nothing to do — all submodule refs are in sync\n")
			outputJSON(output)
			return ExitOK
		}

		parentMsg := *message
		if parentMsg == "" {
			parentMsg = *parentMessage
		}

		parentResult := commitParentRefs(root, targetSubs, parentMsg, *parentFiles)
		output := GitCommitOutput{
			Path:       root,
			Success:    parentResult.Success && parentResult.Pushed,
			Partial:    parentResult.Success && len(parentResult.LeftUncommitted) > 0,
			Submodules: []GitCommitResult{},
			Parent:     &parentResult,
		}
		if !output.Success {
			output.Error = parentResult.Error
			if parentResult.Success && !parentResult.Pushed {
				output.Hint = fmt.Sprintf("parent commit created but not pushed; push with: glittering git push --path %s", root)
				logf("hint: %s\n", output.Hint)
			}
		}

		deleteCache(root, "git.json")
		outputJSON(output)

		if !output.Success {
			return ExitFailure
		}
		if output.Partial {
			return ExitPartial
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
				if h := recoveryHint(subResults, root); h != "" {
					output.Hint = h
					logf("hint: %s\n", h)
				}
				outputJSON(output)
				return ExitFailure
			}
		} else if len(*files) > 0 && i == 0 {
			for _, f := range *files {
				if _, err := runGit(subDir, "add", "--", f); err != nil {
					subResults = append(subResults, GitCommitResult{Path: subPath, Error: fmt.Sprintf("stage failed for %s: %v", f, err)})
					output := GitCommitOutput{Path: root, Submodules: subResults, Error: fmt.Sprintf("stage failed for %s in %s: %v", f, subPath, err)}
					if h := recoveryHint(subResults, root); h != "" {
						output.Hint = h
						logf("hint: %s\n", h)
					}
					outputJSON(output)
					return ExitFailure
				}
			}
		}
		// --staged or no flag: no-op (commit index as-is)

		// Empty-stage check: catch the common "forgot --all/-f" mistake before
		// git commit fails with an unhelpful "nothing to commit" on stdout.
		if _, diffErr := runGit(subDir, "diff", "--cached", "--quiet"); diffErr == nil {
			msg := fmt.Sprintf("nothing staged in %s; pass --all, -f <file>, --staged, or stage manually first", subPath)
			subResults = append(subResults, GitCommitResult{Path: subPath, Error: msg})
			output := GitCommitOutput{Path: root, Submodules: subResults, Error: msg}
			if h := recoveryHint(subResults, root); h != "" {
				output.Hint = h
				logf("hint: %s\n", h)
			}
			outputJSON(output)
			return ExitFailure
		}

		// Commit
		if _, err := runGit(subDir, "commit", "-m", *message); err != nil {
			subResults = append(subResults, GitCommitResult{Path: subPath, Error: fmt.Sprintf("commit failed: %v", err)})
			output := GitCommitOutput{Path: root, Submodules: subResults, Error: fmt.Sprintf("commit failed in %s: %v", subPath, err)}
			if h := recoveryHint(subResults, root); h != "" {
				output.Hint = h
				logf("hint: %s\n", h)
			}
			outputJSON(output)
			return ExitFailure
		}

		ref, _ := runGit(subDir, "rev-parse", "HEAD")

		// Push
		_, pushErr := runGitNet(subDir, "push", "--set-upstream", "origin", "HEAD")
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
			if h := recoveryHint(subResults, root); h != "" {
				output.Hint = h
				logf("hint: %s\n", h)
			}
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
	parentResult := commitParentRefs(root, resolvedSubs, *parentMessage, *parentFiles)
	output.Parent = &parentResult
	output.Partial = parentResult.Success && len(parentResult.LeftUncommitted) > 0

	if !parentResult.Success || !parentResult.Pushed {
		output.Success = false
		output.Error = parentResult.Error
		if !parentResult.Success {
			// Subs are committed+pushed but the ref bump never happened
			output.Hint = recoveryHint(subResults, root)
		} else {
			// Re-running --parent-only would create a duplicate commit; just push
			output.Hint = fmt.Sprintf("parent commit created but not pushed; push with: glittering git push --path %s", root)
		}
		if output.Hint != "" {
			logf("hint: %s\n", output.Hint)
		}
	}

	deleteCache(root, "git.json")
	outputJSON(output)

	if !output.Success {
		return ExitFailure
	}
	if output.Partial {
		return ExitPartial
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
	if entries, err := statusEntries(root); err == nil && len(entries) > 0 {
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
	_, pullErr := runGitNet(root, "pull", "origin", branch)
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
		if _, initErr := runGitNet(root, args...); initErr != nil {
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
		if entries, err := statusEntries(subDir); err == nil && len(entries) > 0 {
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
		if _, err := runGitNet(subDir, "pull", "origin", subBranch); err != nil {
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
