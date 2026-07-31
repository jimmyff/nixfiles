package cmd

import (
	"errors"
	"fmt"
	flag "github.com/spf13/pflag"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
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
		return removeOrphan(proj, metas, names[0], *force, &out)
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
	if err := removeWorktreeDir(proj.CommonDir, target.Path); err != nil {
		return finishRemove(&out, err.Error(), ExitFailure)
	}
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

// removeWorktreeDir removes a worktree directory via git, falling back to
// direct deletion when git fails: git deregisters the admin entry even when
// the working-tree delete fails ("no going back" — builtin/worktree.c), so an
// external writer recreating a file mid-delete (.DS_Store, IDE metadata) would
// otherwise leave an orphan dir git no longer lists. Callers must pass a gated
// path — once git fails, the fallback deletes whatever it was handed. The
// cache tree is dropped only once the directory is actually gone, so a failed
// removal stays visible to a later orphan --force cleanup.
func removeWorktreeDir(commonDir, path string) error {
	if _, gitErr := runGit(commonDir, "worktree", "remove", "--force", path); gitErr != nil {
		if rmErr := removeDirRetry(path); rmErr != nil {
			runGit(commonDir, "worktree", "prune")
			return fmt.Errorf("git worktree remove failed: %v; fallback removal failed: %v", gitErr, rmErr)
		}
		progressf("  git worktree remove failed (%v); removed directory directly\n", gitErr)
	}
	runGit(commonDir, "worktree", "prune")
	deleteCacheTree(path)
	return nil
}

// removeDirRetry deletes a directory tree, retrying when a concurrent writer
// (Finder, an IDE) recreates entries mid-delete — rmdir then fails ENOTEMPTY
// (or EEXIST; POSIX allows either). Anything else (EACCES…) fails fast.
// Refuses relative/empty/root paths — the last line of defense against a
// caller passing an ungated path.
func removeDirRetry(path string) error {
	if !filepath.IsAbs(path) || path == string(filepath.Separator) {
		return fmt.Errorf("refusing to remove non-absolute or root path %q", path)
	}
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(150 * time.Millisecond)
		}
		if err = os.RemoveAll(path); err == nil || !isRetryableRemoveErr(err) {
			return err
		}
	}
	return err
}

// isRetryableRemoveErr reports whether a RemoveAll failure means "something
// recreated an entry mid-delete". RemoveAll returns *fs.PathError wrapping
// the errno, so errors.Is compares the errno directly.
func isRetryableRemoveErr(err error) bool {
	return errors.Is(err, syscall.ENOTEMPTY) || errors.Is(err, syscall.EEXIST)
}

// removeOrphan handles a remove of a name git doesn't know. A directory can
// survive at that path when a prior removal deregistered the worktree but
// failed to delete its files (see removeWorktreeDir); it has no .git file, so
// the dirty/unpushed gate cannot assess it — deleting requires --force.
// Anything else keeps the "no worktree named" answer (policy refusal, exit 0).
func removeOrphan(proj projectInfo, metas []worktreeMeta, name string, force bool, out *WorktreeRemoveOutput) int {
	notFound := fmt.Sprintf("no worktree named %q", name)
	if err := validateWorktreeName(name); err != nil {
		return finishRemove(out, notFound, ExitOK)
	}
	path := filepath.Join(proj.ProjectDir, name)
	if !isOrphanDir(proj, metas, path) {
		return finishRemove(out, notFound, ExitOK)
	}
	out.Path = path
	if !force {
		return finishRemove(out, fmt.Sprintf(
			"%s is not a registered worktree but its directory still exists (orphan from a failed removal); rerun with --force to delete the directory and its cache", name), ExitOK)
	}
	if err := removeDirRetry(path); err != nil {
		return finishRemove(out, fmt.Sprintf("orphan removal failed: %v", err), ExitFailure)
	}
	deleteCacheTree(path)
	out.Removed = true
	outputJSON(out)
	return ExitOK
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
