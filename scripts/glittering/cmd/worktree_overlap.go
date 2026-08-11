package cmd

import (
	"path/filepath"
	"sort"
)

// submodulesAheadOfPin names the worktree's submodules whose clone carries
// commits the parent's pinned ref doesn't — unlanded submodule work. Cheap by
// construction: it reuses the caller's `git submodule status` snapshot, then
// runs a rev-list only for the entries git already flags as differing from the
// pin ('+'), which separates "ahead" from the merely stale ones `git sync` fixes.
func submodulesAheadOfPin(wtPath string, entries []submoduleStatusEntry) []string {
	var ahead []string
	for _, entry := range entries {
		if entry.Flag != '+' {
			continue
		}
		pin := getParentPin(wtPath, entry.Path)
		if pin == "" {
			continue
		}
		subDir := filepath.Join(wtPath, entry.Path)
		head, err := runGit(subDir, "rev-parse", "HEAD")
		if err != nil {
			continue
		}
		if _, headOnly := getRevListCount(subDir, pin, head); headOnly > 0 {
			ahead = append(ahead, entry.Path)
		}
	}
	return ahead
}

// computeOverlaps folds per-worktree ahead-of-pin submodules into the
// project-level collision report: a submodule carrying local commits in two or
// more worktrees is where concurrent agents will collide, and seeing it before
// spawning the second agent is the whole point. Pure — unit-tested.
func computeOverlaps(rows []WorktreeInfo) []WorktreeOverlap {
	bySubmodule := map[string][]string{}
	for _, row := range rows {
		for _, sub := range row.SubmodulesAhead {
			bySubmodule[sub] = append(bySubmodule[sub], row.Name)
		}
	}
	overlaps := []WorktreeOverlap{}
	for sub, names := range bySubmodule {
		if len(names) < 2 {
			continue
		}
		overlaps = append(overlaps, WorktreeOverlap{Submodule: sub, Worktrees: names})
	}
	sort.Slice(overlaps, func(i, j int) bool { return overlaps[i].Submodule < overlaps[j].Submodule })
	return overlaps
}
