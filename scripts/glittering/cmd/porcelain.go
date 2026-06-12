package cmd

import "strings"

// porcelainEntry is one parsed entry from `git status --porcelain -z`.
type porcelainEntry struct {
	X    byte   // index status column
	Y    byte   // working-tree status column
	Path string // current path (the rename/copy target)
}

// parsePorcelainZ parses NUL-separated `git status --porcelain -z` output.
// The input must come from runGitRaw, untrimmed: the first entry's index
// column may be a meaningful space (regression: a trimmed first line shifted
// the columns, misclassifying an unstaged file as staged and truncating its
// name — "PROJECT_PLAN.md" became "ROJECT_PLAN.md").
func parsePorcelainZ(out string) []porcelainEntry {
	var entries []porcelainEntry
	tokens := strings.Split(out, "\x00")
	for i := 0; i < len(tokens); i++ {
		t := tokens[i]
		if len(t) < 4 || t[2] != ' ' {
			continue
		}
		e := porcelainEntry{X: t[0], Y: t[1], Path: t[3:]}
		// Rename/copy entries are followed by a separate origin-path token.
		if e.X == 'R' || e.X == 'C' || e.Y == 'R' || e.Y == 'C' {
			i++
		}
		entries = append(entries, e)
	}
	return entries
}

// statusEntries returns the parsed `git status` entries for dir. The -z
// format also yields exact paths (no quoting of names with spaces).
func statusEntries(dir string) ([]porcelainEntry, error) {
	out, err := runGitRaw(dir, "status", "--porcelain", "-z")
	if err != nil {
		return nil, err
	}
	return parsePorcelainZ(out), nil
}

// untrackedPaths returns the paths of untracked entries.
func untrackedPaths(entries []porcelainEntry) []string {
	var paths []string
	for _, e := range entries {
		if e.X == '?' && e.Y == '?' {
			paths = append(paths, e.Path)
		}
	}
	return paths
}

// countUntracked counts untracked entries.
func countUntracked(entries []porcelainEntry) int {
	return len(untrackedPaths(entries))
}
