package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"os"
	"path/filepath"
	"strings"
)

// worktreeRemove removes a worktree behind a safety gate. Policy refusals
// (base/current/dirty/unpushed) answer the query with removed:false + reasons
// and exit 0; only git/IO failure is ExitFailure.
func worktreeRemove(args []string) int {
	fs := flag.NewFlagSet("worktree remove", flag.ExitOnError)
	path := fs.String("path", ".", "path inside the project")
	force := fs.Bool("force", false, "remove even if dirty/unpushed")
	deleteBranch := fs.Bool("delete-branch", false, "also delete the branch (safe -d only)")
	fetch := fs.Bool("fetch", false, "fetch remotes before the safety gate")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	names := fs.Args()
	if len(names) != 1 {
		logf("error: worktree remove requires exactly one <name>\n")
		return ExitUsage
	}
	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}
	proj, metas, err := discoverWorktrees(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	out := WorktreeRemoveOutput{Name: names[0], Reasons: []string{}}

	// Resolve first — a non-match returns before any deletion (cache blast guard).
	target, ok := resolveWorktreeTarget(metas, names[0])
	if !ok {
		return finishRemove(&out, fmt.Sprintf("no worktree named %q", names[0]), ExitOK)
	}
	out.Name, out.Path = target.Name, target.Path

	if target.Name == proj.BaseBranch || target.Branch == proj.BaseBranch {
		return finishRemove(&out, "refusing to remove the base worktree", ExitOK)
	}
	if isCurrentWorktree(proj, target) {
		return finishRemove(&out, "refusing to remove the current worktree", ExitOK)
	}

	if *fetch {
		if _, err := runGitNet(proj.CommonDir, "fetch", "origin"); err != nil {
			progressf("  warning: fetch failed: %v\n", err)
		}
	}

	if !*force {
		if reasons := removeBlockers(target); len(reasons) > 0 {
			out.Reasons = append(out.Reasons, reasons...)
			outputJSON(out)
			return ExitOK
		}
	}

	// Our gate (above) is the authoritative safety check; force at the git level
	// so a clean worktree containing submodules isn't refused by git's own check.
	if _, err := runGit(proj.CommonDir, "worktree", "remove", "--force", target.Path); err != nil {
		return finishRemove(&out, fmt.Sprintf("git worktree remove failed: %v", err), ExitFailure)
	}
	runGit(proj.CommonDir, "worktree", "prune")
	deleteCacheTree(target.Path)
	out.Removed = true

	if *deleteBranch && target.Branch != "" {
		// Safe -d only: never force-delete an unmerged branch.
		if _, err := runGit(proj.CommonDir, "branch", "-d", target.Branch); err != nil {
			out.Reasons = append(out.Reasons,
				fmt.Sprintf("branch %q not deleted (unmerged?) — delete manually with: git branch -D %s", target.Branch, target.Branch))
		} else {
			out.BranchDeleted = true
		}
	}

	outputJSON(out)
	return ExitOK
}

// finishRemove appends a reason, emits the output, and returns the exit code.
func finishRemove(out *WorktreeRemoveOutput, reason string, code int) int {
	out.Reasons = append(out.Reasons, reason)
	outputJSON(out)
	return code
}

// isCurrentWorktree refuses the worktree containing --path, or the one the
// process is standing in (git -C commonDir wouldn't otherwise stop us).
func isCurrentWorktree(proj projectInfo, target worktreeMeta) bool {
	if proj.CurrentPath != "" && proj.CurrentPath == target.Path {
		return true
	}
	wd, err := os.Getwd()
	if err != nil {
		return false
	}
	resolved, err := filepath.EvalSymlinks(wd)
	if err != nil {
		return false
	}
	rel, err := filepath.Rel(target.Path, resolved)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// removeBlockers returns reasons a worktree shouldn't be dropped: uncommitted
// changes, stash, or commits not on any remote — across the superproject and
// every submodule. It keys on HeadOnRemote (HEAD reachable from some remote
// branch) rather than the "detached" flag: submodules are normally in detached
// HEAD at their pinned ref, which is clean, not a blocker. !HeadOnRemote is the
// authoritative "unpushed work" signal (and also catches a clean local-only
// commit with no upstream, which emits no ahead/behind).
func removeBlockers(target worktreeMeta) []string {
	data, err := collectGitData(target.Path, false)
	if err != nil {
		return []string{fmt.Sprintf("could not assess worktree: %v", err)}
	}
	var reasons []string
	if data.Repo.Dirty {
		reasons = append(reasons, "uncommitted changes")
	}
	if data.Repo.StashCount > 0 {
		reasons = append(reasons, fmt.Sprintf("%d stash entry(ies)", data.Repo.StashCount))
	}
	if !data.Repo.HeadOnRemote {
		reasons = append(reasons, "HEAD has commits not on any remote (unpushed)")
	}
	for _, sub := range data.Submodules {
		if sub.Dirty {
			reasons = append(reasons, fmt.Sprintf("submodule %s: uncommitted changes", sub.Path))
		}
		if !sub.HeadOnRemote {
			reasons = append(reasons, fmt.Sprintf("submodule %s: unpushed commits", sub.Path))
		}
		if sub.StashCount > 0 {
			reasons = append(reasons, fmt.Sprintf("submodule %s: stash entries", sub.Path))
		}
	}
	return reasons
}
