package cmd

import (
	flag "github.com/spf13/pflag"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// GitDiff produces a structured diff summary for the parent repo and all submodules.
func GitDiff(args []string) int {
	fs := flag.NewFlagSet("git diff", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	stagedOnly := fs.Bool("staged", false, "only show staged changes")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	session, err := createSession()
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if err := ensureSessionSubdir(session, "diff"); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	progressf("glittering: collecting diffs in %s\n", root)

	var repos []DiffRepoResult
	summary := DiffSummary{}

	// Parent repo
	if result := collectRepoDiff(".", root, session, *stagedOnly); result != nil {
		repos = append(repos, *result)
	}

	// Submodules
	submodulePaths, err := getSubmodulePaths(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	for _, subPath := range submodulePaths {
		absDir := filepath.Join(root, subPath)
		if result := collectRepoDiff(subPath, absDir, session, *stagedOnly); result != nil {
			repos = append(repos, *result)
		}
	}

	// Aggregate summary
	for _, r := range repos {
		summary.DirtyRepos++
		summary.TotalFiles += r.TotalFiles
		summary.TotalInsertions += r.TotalInsertions
		summary.TotalDeletions += r.TotalDeletions
		summary.TotalUntracked += len(r.UntrackedFiles)
	}

	if repos == nil {
		repos = []DiffRepoResult{}
	}

	out := DiffOutput{
		Path:    root,
		Session: session,
		Repos:   repos,
		Summary: summary,
	}
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	return ExitOK
}

// collectRepoDiff gathers diff info for a single repo. Returns nil if clean.
func collectRepoDiff(repoPath, absDir, session string, stagedOnly bool) *DiffRepoResult {
	staged := parseDiffFiles(absDir, true)
	var unstaged []DiffChangedFile
	if !stagedOnly {
		unstaged = parseDiffFiles(absDir, false)
	}

	// Untracked files
	var untracked []string
	porcelain, err := runGit(absDir, "status", "--porcelain")
	if err == nil && porcelain != "" {
		for _, line := range strings.Split(porcelain, "\n") {
			if strings.HasPrefix(line, "??") {
				file := strings.TrimSpace(strings.TrimPrefix(line, "??"))
				untracked = append(untracked, file)
			}
		}
	}

	if len(staged) == 0 && len(unstaged) == 0 && len(untracked) == 0 {
		return nil
	}

	// Ensure non-nil slices for JSON
	if staged == nil {
		staged = []DiffChangedFile{}
	}
	if unstaged == nil {
		unstaged = []DiffChangedFile{}
	}
	if untracked == nil {
		untracked = []string{}
	}

	// Compute totals (deduplicate files across staged/unstaged)
	fileSet := map[string]bool{}
	totalIns, totalDel := 0, 0
	for _, f := range staged {
		fileSet[f.Path] = true
		totalIns += f.Insertions
		totalDel += f.Deletions
	}
	for _, f := range unstaged {
		fileSet[f.Path] = true
		totalIns += f.Insertions
		totalDel += f.Deletions
	}

	// Write .patch detail file
	var detailsFile string
	var patchParts []string
	cachedDiff, err := runGit(absDir, "diff", "--cached")
	if err == nil && cachedDiff != "" {
		patchParts = append(patchParts, "# Staged changes\n"+cachedDiff)
	}
	if !stagedOnly {
		workingDiff, err := runGit(absDir, "diff")
		if err == nil && workingDiff != "" {
			patchParts = append(patchParts, "# Unstaged changes\n"+workingDiff)
		}
	}
	if len(patchParts) > 0 {
		patchFile := filepath.Join(session, "diff", safePath(repoPath)+".patch")
		if err := os.WriteFile(patchFile, []byte(strings.Join(patchParts, "\n\n")), 0644); err != nil {
			logf("  warning: could not write patch file for %s: %v\n", repoPath, err)
		} else {
			detailsFile = patchFile
		}
	}

	// Get branch
	branch, _ := runGit(absDir, "branch", "--show-current")

	progressf("  %s: %d files (+%d/-%d), %d untracked\n", repoPath, len(fileSet), totalIns, totalDel, len(untracked))

	return &DiffRepoResult{
		Path:            repoPath,
		Branch:          branch,
		Staged:          staged,
		Unstaged:        unstaged,
		UntrackedFiles:  untracked,
		TotalFiles:      len(fileSet),
		TotalInsertions: totalIns,
		TotalDeletions:  totalDel,
		DetailsFile:     detailsFile,
	}
}

// parseDiffFiles returns changed files with status codes and insertion/deletion counts.
func parseDiffFiles(dir string, cached bool) []DiffChangedFile {
	// Get status codes
	nameStatusArgs := []string{"diff", "--name-status"}
	if cached {
		nameStatusArgs = append(nameStatusArgs, "--cached")
	}
	nameStatusOut, err := runGit(dir, nameStatusArgs...)
	if err != nil || nameStatusOut == "" {
		return nil
	}

	// Get insertion/deletion counts
	numstatArgs := []string{"diff", "--numstat"}
	if cached {
		numstatArgs = append(numstatArgs, "--cached")
	}
	numstatOut, err := runGit(dir, numstatArgs...)

	// Parse numstat into map[path] -> (ins, del)
	type stats struct {
		ins, del int
	}
	numstatMap := map[string]stats{}
	if err == nil && numstatOut != "" {
		for _, line := range strings.Split(numstatOut, "\n") {
			parts := strings.SplitN(line, "\t", 3)
			if len(parts) != 3 {
				continue
			}
			ins, _ := strconv.Atoi(parts[0]) // "-" for binary -> 0
			del, _ := strconv.Atoi(parts[1])
			// For renames, numstat shows the new path
			p := parts[2]
			// Handle rename format: old => new or {old => new}
			if idx := strings.Index(p, " => "); idx >= 0 {
				p = extractRenamePath(p)
			}
			numstatMap[p] = stats{ins, del}
		}
	}

	// Parse name-status and merge with numstat
	var files []DiffChangedFile
	for _, line := range strings.Split(nameStatusOut, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.SplitN(line, "\t", 3)
		if len(fields) < 2 {
			continue
		}
		statusCode := fields[0]
		var filePath string

		// Renames: R100\told\tnew
		if strings.HasPrefix(statusCode, "R") {
			statusCode = "R"
			if len(fields) >= 3 {
				filePath = fields[2] // new path
			} else {
				filePath = fields[1]
			}
		} else {
			filePath = fields[1]
		}

		s := numstatMap[filePath]
		files = append(files, DiffChangedFile{
			Path:       filePath,
			Status:     statusCode,
			Insertions: s.ins,
			Deletions:  s.del,
		})
	}

	return files
}

// extractRenamePath extracts the new path from numstat rename formats.
// Formats: "old => new" or "prefix/{old => new}/suffix"
func extractRenamePath(p string) string {
	if idx := strings.Index(p, "{"); idx >= 0 {
		// Format: prefix/{old => new}/suffix
		closeIdx := strings.Index(p, "}")
		if closeIdx < 0 {
			return p
		}
		prefix := p[:idx]
		suffix := p[closeIdx+1:]
		inner := p[idx+1 : closeIdx]
		arrowIdx := strings.Index(inner, " => ")
		if arrowIdx < 0 {
			return p
		}
		newPart := inner[arrowIdx+4:]
		return prefix + newPart + suffix
	}
	// Format: old => new
	arrowIdx := strings.Index(p, " => ")
	if arrowIdx >= 0 {
		return p[arrowIdx+4:]
	}
	return p
}
