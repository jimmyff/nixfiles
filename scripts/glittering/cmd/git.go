package cmd

import (
	"encoding/json"
	"fmt"
	flag "github.com/spf13/pflag"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
)

const gitHelpText = `glittering git — Git operations across parent repo and submodules

Subcommands:
  (default)      Fetch remotes and show status (branch, dirty, ahead/behind)
  check          Verify everything is committed, pushed, and refs are in sync
  push           Push all repos with unpushed commits
  commit         Commit submodules and auto-update parent ref
  pull           Pull parent, checkout branches, pull all submodules
  diff           Structured diff summary across all repos

Status flags:
  -path string    repository root path (default ".")
  -skip-fetch     skip fetching from remotes
  -cached         read from cache instead of running live

Run 'glittering git <subcommand> -help' for subcommand-specific flags.
`

// Git dispatches to git subcommands.
func Git(args []string) int {
	if len(args) == 0 {
		return gitStatus(args)
	}
	switch args[0] {
	case "-help", "--help", "help":
		fmt.Fprint(os.Stderr, gitHelpText)
		return ExitOK
	case "commit":
		return GitCommit(args[1:])
	case "commit-sub":
		logf("error: 'git commit-sub' has been removed — use: glittering git commit <sub> -m \"msg\" [--all|-f <file>|--staged]\n")
		return ExitUsage
	case "commit-parent":
		logf("error: 'git commit-parent' has been removed — use: glittering git commit --parent-only [sub...]\n")
		return ExitUsage
	case "pull":
		return GitPull(args[1:])
	case "diff":
		return GitDiff(args[1:])
	case "check":
		return GitCheck(args[1:])
	case "push":
		return GitPush(args[1:])
	default:
		// No recognized subcommand — treat all args as flags for git status
		return gitStatus(args)
	}
}

// collectGitData fetches remotes (if requested) and collects status for parent + submodules.
// Fetches and status checks run concurrently across submodules with bounded parallelism.
func collectGitData(root string, fetch bool) (GitOutput, error) {
	if fetch {
		progressf("glittering: fetching remotes in %s\n", root)
	} else {
		progressf("glittering: checking git status in %s\n", root)
	}

	repo, err := getRepoStatus(root)
	if err != nil {
		return GitOutput{}, err
	}

	submodulePaths, err := getSubmodulePaths(root)
	if err != nil {
		return GitOutput{}, err
	}

	const maxJobs = 8

	// Phase 1: Parallel fetch
	if fetch {
		if _, err := runGitNet(root, "fetch", "origin"); err != nil {
			progressf("  warning: fetch failed for parent: %v\n", err)
		}
		sem := make(chan struct{}, maxJobs)
		var wg sync.WaitGroup
		var mu sync.Mutex
		for _, subPath := range submodulePaths {
			wg.Add(1)
			sem <- struct{}{}
			go func(sp string) {
				defer wg.Done()
				defer func() { <-sem }()
				subDir := filepath.Join(root, sp)
				if _, err := runGitNet(subDir, "fetch", "origin"); err != nil {
					mu.Lock()
					progressf("  warning: fetch failed for %s: %v\n", sp, err)
					mu.Unlock()
				}
			}(subPath)
		}
		wg.Wait()
	}

	// Phase 2: Parallel status collection (indexed results preserve ordering)
	type indexedResult struct {
		index  int
		result GitSubmoduleStatus
	}
	resultsCh := make(chan indexedResult, len(submodulePaths))
	sem := make(chan struct{}, maxJobs)

	var mu sync.Mutex
	for i, subPath := range submodulePaths {
		sem <- struct{}{}
		mu.Lock()
		progressf("  checking %s...\n", subPath)
		mu.Unlock()
		go func(i int, sp string) {
			result := getSubmoduleStatus(root, sp)
			resultsCh <- indexedResult{index: i, result: result}
			<-sem
		}(i, subPath)
	}

	submodules := make([]GitSubmoduleStatus, len(submodulePaths))
	for range submodulePaths {
		ir := <-resultsCh
		submodules[ir.index] = ir.result
	}

	out := GitOutput{
		Path:       root,
		Timestamp:  nowTimestamp(),
		Repo:       repo,
		Submodules: submodules,
	}
	if len(out.Submodules) == 0 {
		out.Submodules = []GitSubmoduleStatus{}
	}
	return out, nil
}

func gitStatus(args []string) int {
	fs := flag.NewFlagSet("git", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	skipFetch := fs.Bool("skip-fetch", false, "skip fetching from remotes")
	cached := fs.Bool("cached", false, "read from cache instead of running live")
	filter := fs.String("filter", "", "comma-separated submodule name filters")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	if *cached && *skipFetch {
		logf("error: --cached and --skip-fetch are mutually exclusive\n")
		return ExitUsage
	}

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Cached mode: return cache file or empty output
	if *cached {
		data, err := readCache(root, "git.json")
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		if data != nil {
			filters := parseFilter(*filter)
			if len(filters) > 0 {
				var gitOut GitOutput
				if err := json.Unmarshal(data, &gitOut); err == nil {
					gitOut.Submodules = filterGitSubmodulesWithParent(gitOut.Submodules, filters)
					outputJSON(gitOut)
					return ExitOK
				}
			}
			os.Stdout.Write(data)
			return ExitOK
		}
		out := GitOutput{Path: root, Submodules: []GitSubmoduleStatus{}}
		if err := outputJSON(out); err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		return ExitOK
	}

	out, err := collectGitData(root, !*skipFetch)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	// Always write full (unfiltered) data to cache
	writeCache(root, "git.json", out)
	// Then filter for output
	filters := parseFilter(*filter)
	out.Submodules = filterGitSubmodulesWithParent(out.Submodules, filters)
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	return ExitOK
}

func getRepoStatus(root string) (GitRepoStatus, error) {
	status := GitRepoStatus{Path: "."}

	branch, err := runGit(root, "branch", "--show-current")
	if err == nil {
		status.Branch = branch
	}

	ref, err := runGit(root, "rev-parse", "HEAD")
	if err == nil {
		status.Ref = ref
	}

	entries, err := statusEntries(root)
	if err == nil {
		status.Dirty = len(entries) > 0
		status.UntrackedFiles = untrackedPaths(entries)
	}

	status.Detached = status.Branch == ""

	us := getUpstreamStatus(root, status.Branch)
	status.Upstream = us.Upstream
	status.AheadRemote = us.Ahead
	status.BehindRemote = us.Behind
	status.HeadOnRemote = isHeadOnRemote(root)
	status.StashCount = getStashCount(root)
	status.UntrackedCount = len(status.UntrackedFiles)

	if msg, err := runGit(root, "log", "--oneline", "-1"); err == nil {
		status.LatestCommit = msg
	}

	return status, nil
}

func getSubmodulePaths(root string) ([]string, error) {
	output, err := runGit(root, "submodule", "status")
	if err != nil {
		return nil, err
	}
	if output == "" {
		return nil, nil
	}
	var paths []string
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		// Format: [+-U ]<sha1> <path> [(describe)]
		// Leading char may be +, -, U, or space
		if len(line) > 0 && (line[0] == '+' || line[0] == '-' || line[0] == 'U' || line[0] == ' ') {
			line = line[1:]
		}
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			paths = append(paths, parts[1])
		}
	}
	return paths, nil
}

func getSubmoduleStatus(root, subPath string) GitSubmoduleStatus {
	subDir := filepath.Join(root, subPath)
	sub := GitSubmoduleStatus{Path: subPath}

	// Get branch
	branch, err := runGit(subDir, "branch", "--show-current")
	if err == nil {
		sub.Branch = branch
		sub.Detached = branch == ""
	}

	// Get HEAD ref
	ref, err := runGit(subDir, "rev-parse", "HEAD")
	if err == nil {
		sub.Ref = ref
	}

	// Get parent's recorded ref via ls-tree
	parentRef, err := runGit(root, "ls-tree", "HEAD", subPath)
	if err == nil && parentRef != "" {
		// Format: <mode> commit <sha>\t<path>
		fields := strings.Fields(parentRef)
		if len(fields) >= 3 {
			sub.ParentRef = fields[2]
		}
	}

	// Check dirty + count untracked
	entries, err := statusEntries(subDir)
	if err == nil {
		sub.Dirty = len(entries) > 0
		sub.UntrackedCount = countUntracked(entries)
	}

	// Ahead/behind remote (uses real upstream, not hardcoded origin/<branch>)
	us := getUpstreamStatus(subDir, sub.Branch)
	sub.Upstream = us.Upstream
	sub.AheadRemote = us.Ahead
	sub.BehindRemote = us.Behind

	// Check if HEAD is on any remote branch (works for detached HEAD too)
	sub.HeadOnRemote = isHeadOnRemote(subDir)
	sub.StashCount = getStashCount(subDir)

	// Ahead/behind parent ref
	if sub.Ref != "" && sub.ParentRef != "" && sub.Ref != sub.ParentRef {
		sub.BehindParent, sub.AheadParent = getRevListCount(subDir, sub.ParentRef, sub.Ref)
	}

	// Latest commit message
	msg, err := runGit(subDir, "log", "--oneline", "-1")
	if err == nil {
		sub.LatestCommit = msg
	}

	return sub
}

// getUninitialisedSubmodules returns submodule paths that have a leading '-' in
// git submodule status output, indicating they haven't been cloned yet.
func getUninitialisedSubmodules(root string) []string {
	output, err := runGit(root, "submodule", "status")
	if err != nil || output == "" {
		return nil
	}
	var paths []string
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if len(line) > 0 && line[0] == '-' {
			parts := strings.Fields(line[1:])
			if len(parts) >= 2 {
				paths = append(paths, parts[1])
			}
		}
	}
	return paths
}

// branchForCommit returns the origin-tracked branch that contains commit,
// preferring main, or "" if none. Used to attach a detached submodule to the
// branch its pinned ref lives on — never origin/HEAD, which can be a stale
// 'master' that has drifted from the pin.
func branchForCommit(dir, commit string) string {
	out, err := runGit(dir, "for-each-ref", "--contains", commit, "--format=%(refname)", "refs/remotes/origin/*")
	if err != nil {
		return ""
	}
	var first string
	for _, line := range strings.Split(out, "\n") {
		name := strings.TrimPrefix(strings.TrimSpace(line), "refs/remotes/origin/")
		if name == "" || name == "HEAD" {
			continue
		}
		if name == "main" {
			return "main"
		}
		if first == "" {
			first = name
		}
	}
	return first
}

// getSubmoduleBranch determines the correct branch for a submodule.
// Priority: .gitmodules config > current branch > branch containing HEAD (prefer
// main) > "main".
func getSubmoduleBranch(root, subPath string) string {
	// 1. Check .gitmodules for configured tracking branch
	configKey := fmt.Sprintf("submodule.%s.branch", subPath)
	if branch, err := runGit(root, "config", "-f", ".gitmodules", configKey); err == nil && branch != "" {
		return branch
	}

	// 2. Check current branch in submodule
	subDir := filepath.Join(root, subPath)
	if branch, err := runGit(subDir, "branch", "--show-current"); err == nil && branch != "" {
		return branch
	}

	// 3. Detached: the branch containing the checked-out (pinned) commit, prefer
	// main; never assume a bare "main" (a master-only submodule has none).
	if branch := branchForCommit(subDir, "HEAD"); branch != "" {
		return branch
	}
	return "main"
}

type upstreamInfo struct {
	Upstream string
	Ahead    int
	Behind   int
}

// getUpstreamStatus resolves the actual upstream tracking branch and computes ahead/behind.
// Falls back to origin/<branch> if no upstream is configured. Returns empty Upstream
// when no remote ref can be found (signals "no tracking").
func getUpstreamStatus(dir, branch string) upstreamInfo {
	if branch == "" {
		return upstreamInfo{}
	}

	// Try real upstream: git rev-parse --abbrev-ref <branch>@{upstream}
	upstream, err := runGit(dir, "rev-parse", "--abbrev-ref", branch+"@{upstream}")
	if err != nil {
		// Fall back to origin/<branch> if it exists
		fallback := fmt.Sprintf("origin/%s", branch)
		if _, verifyErr := runGit(dir, "rev-parse", "--verify", fallback); verifyErr != nil {
			return upstreamInfo{} // no tracking ref at all
		}
		upstream = fallback
	}

	output, err := runGit(dir, "rev-list", "--left-right", "--count", fmt.Sprintf("HEAD...%s", upstream))
	if err != nil {
		return upstreamInfo{Upstream: upstream}
	}
	ahead, behind := parseLeftRight(output)
	return upstreamInfo{Upstream: upstream, Ahead: ahead, Behind: behind}
}

// isHeadOnRemote returns true if HEAD exists on any remote branch.
func isHeadOnRemote(dir string) bool {
	branches, err := runGit(dir, "branch", "-r", "--contains", "HEAD")
	return err == nil && strings.TrimSpace(branches) != ""
}

// getStashCount returns the number of stash entries.
func getStashCount(dir string) int {
	output, err := runGit(dir, "stash", "list")
	if err != nil || output == "" {
		return 0
	}
	return len(strings.Split(output, "\n"))
}

func getRevListCount(dir, base, head string) (int, int) {
	output, err := runGit(dir, "rev-list", "--left-right", "--count", fmt.Sprintf("%s...%s", base, head))
	if err != nil {
		return 0, 0
	}
	return parseLeftRight(output)
}

func parseLeftRight(output string) (int, int) {
	parts := strings.Fields(output)
	if len(parts) != 2 {
		return 0, 0
	}
	// rev-list --left-right returns: left\tright
	// left = commits in first ref not in second (behind for HEAD...origin = origin ahead)
	// When comparing HEAD...origin/branch: left=ahead, right=behind
	left, _ := strconv.Atoi(parts[0])
	right, _ := strconv.Atoi(parts[1])
	return left, right
}
