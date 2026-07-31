package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
)

// worktreePrune removes merged-and-pushed worktrees (worktree dirs only; never
// deletes branches — they survive in the bare repo).
func worktreePrune(args []string) int {
	fs := flag.NewFlagSet("worktree prune", flag.ExitOnError)
	path := fs.String("path", ".", "path inside the project")
	dryRun := fs.Bool("dry-run", false, "list candidates without removing")
	force := fs.Bool("force", false, "also reap clean+pushed but unmerged worktrees")
	fetch := fs.Bool("fetch", false, "fetch remotes before evaluating")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

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
	if *fetch {
		if _, err := runGitNet(proj.CommonDir, "fetch", "origin"); err != nil {
			progressf("  warning: fetch failed: %v\n", err)
		}
	}
	out := WorktreePruneOutput{DryRun: *dryRun, Pruned: []WorktreePruneEntry{}, Skipped: []WorktreePruneEntry{}}
	for _, row := range collectWorktreeRows(proj, metas, false) {
		entry := WorktreePruneEntry{Name: row.Name, Path: row.Path, Branch: row.Branch}
		if ok, reason := pruneEligible(row, proj, *force); !ok {
			entry.Reason = reason
			out.Skipped = append(out.Skipped, entry)
			continue
		}
		if *dryRun {
			out.Pruned = append(out.Pruned, entry)
			continue
		}
		// Eligibility (above) is the safety check; force handles submodule worktrees.
		if err := removeWorktreeDir(proj.CommonDir, row.Path); err != nil {
			entry.Reason = fmt.Sprintf("remove failed: %v", err)
			out.Skipped = append(out.Skipped, entry)
			continue
		}
		out.Pruned = append(out.Pruned, entry)
	}
	// After removals, so only pre-existing orphaned caches are reported —
	// just-pruned worktrees' caches are already gone via removeWorktreeDir.
	gc, gcErr := pruneCacheOrphans(proj.ProjectDir, *dryRun)
	if gcErr != nil {
		logf("  cache warning: %v\n", gcErr)
	}
	out.CacheRemoved = gc
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	return ExitOK
}

// pruneEligible decides whether a worktree can be reaped. Conservative default
// (merged into base); --force allows clean+pushed-but-unmerged (work is safe on
// the remote).
func pruneEligible(row WorktreeInfo, proj projectInfo, force bool) (bool, string) {
	switch {
	case row.Current:
		return false, "current worktree"
	case row.Name == proj.BaseBranch:
		return false, "base worktree"
	case row.Dirty:
		return false, "dirty"
	case row.UninitSubmodules > 0:
		return false, "uninitialised submodules"
	case !row.HeadOnRemote:
		return false, "not pushed"
	case row.AheadBase == 0:
		return true, ""
	case force:
		return true, ""
	default:
		return false, "not merged into base"
	}
}
