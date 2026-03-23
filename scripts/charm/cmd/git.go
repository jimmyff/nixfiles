package cmd

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const gitHelpText = `charm git — Git operations across parent repo and submodules

Subcommands:
  (default)      Fetch remotes and show status (branch, dirty, ahead/behind)
  commit-sub     Commit and push a single submodule
  commit-parent  Stage submodule refs, commit and push parent repo
  pull           Pull parent repo and sync submodules
  update         Pull latest in each submodule from its remote
  diff           Structured diff summary across all repos

Status flags:
  -path string    repository root path (default ".")
  -skip-fetch     skip fetching from remotes
  -cached         read from cache instead of running live

Run 'charm git <subcommand> -help' for subcommand-specific flags.
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
	case "commit-sub":
		return GitCommitSub(args[1:])
	case "commit-parent":
		return GitCommitParent(args[1:])
	case "pull":
		return GitPull(args[1:])
	case "update":
		return GitUpdate(args[1:])
	case "diff":
		return GitDiff(args[1:])
	default:
		// No recognized subcommand — treat all args as flags for git status
		return gitStatus(args)
	}
}

func gitStatus(args []string) int {
	fs := flag.NewFlagSet("git", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	skipFetch := fs.Bool("skip-fetch", false, "skip fetching from remotes")
	cached := fs.Bool("cached", false, "read from cache instead of running live")
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

	fetch := !*skipFetch

	if fetch {
		logf("charm: fetching remotes in %s\n", root)
	} else {
		logf("charm: checking git status in %s\n", root)
	}

	// Fetch parent repo
	if fetch {
		if _, err := runGit(root, "fetch", "origin"); err != nil {
			logf("  warning: fetch failed for parent: %v\n", err)
		}
	}

	repo, err := getRepoStatus(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	submodulePaths, err := getSubmodulePaths(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	// Fetch all submodules
	if fetch {
		for _, subPath := range submodulePaths {
			subDir := filepath.Join(root, subPath)
			if _, err := runGit(subDir, "fetch", "origin"); err != nil {
				logf("  warning: fetch failed for %s: %v\n", subPath, err)
			}
		}
	}

	var submodules []GitSubmoduleStatus
	for _, subPath := range submodulePaths {
		sub := getSubmoduleStatus(root, subPath)
		submodules = append(submodules, sub)
	}

	out := GitOutput{
		Path:       root,
		Timestamp:  nowTimestamp(),
		Repo:       repo,
		Submodules: submodules,
	}
	if out.Submodules == nil {
		out.Submodules = []GitSubmoduleStatus{}
	}
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	writeCache(root, "git.json", out)
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

	porcelain, err := runGit(root, "status", "--porcelain")
	if err == nil {
		status.Dirty = porcelain != ""
		if porcelain != "" {
			for _, line := range strings.Split(porcelain, "\n") {
				if strings.HasPrefix(line, "??") {
					file := strings.TrimSpace(strings.TrimPrefix(line, "??"))
					status.UntrackedFiles = append(status.UntrackedFiles, file)
				}
			}
		}
	}

	us := getUpstreamStatus(root, status.Branch)
	status.Upstream = us.Upstream
	status.Ahead = us.Ahead
	status.Behind = us.Behind
	status.HeadOnRemote = isHeadOnRemote(root)
	status.StashCount = getStashCount(root)

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
	porcelain, err := runGit(subDir, "status", "--porcelain")
	if err == nil {
		sub.Dirty = porcelain != ""
		sub.UntrackedCount = countUntracked(porcelain)
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

// countUntracked counts lines starting with "??" in porcelain output.
func countUntracked(porcelain string) int {
	if porcelain == "" {
		return 0
	}
	count := 0
	for _, line := range strings.Split(porcelain, "\n") {
		if strings.HasPrefix(line, "??") {
			count++
		}
	}
	return count
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
