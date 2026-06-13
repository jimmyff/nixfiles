package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// verbose controls whether progress messages are printed.
var verbose bool

// logf prints a message to stderr (always — for errors, hints, warnings).
func logf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, format, args...)
}

// progressf prints a progress message to stderr only when verbose is true.
func progressf(format string, args ...interface{}) {
	if verbose {
		fmt.Fprintf(os.Stderr, "\033[90m"+format+"\033[0m", args...)
	}
}

// progressPrint writes a pre-formatted progress string to stderr in grey (verbose only).
func progressPrint(s string) {
	if verbose && s != "" {
		fmt.Fprintf(os.Stderr, "\033[90m%s\033[0m", s)
	}
}

// outputJSON writes v as indented JSON to stdout.
func outputJSON(v interface{}) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

// safePath converts a relative path to a safe filename (/ -> --).
// The parent repo's path "." maps to "_parent": a literal "." would produce
// hidden, ..-like filenames (e.g. "..patch"), and the underscore prefix avoids
// colliding with any real package/submodule named "parent" (which has no prefix).
func safePath(p string) string {
	if p == "." {
		return "_parent"
	}
	return strings.ReplaceAll(p, "/", "--")
}

// writeJSONFile writes v as indented JSON to the given absolute path.
func writeJSONFile(path string, v interface{}) error {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

// runCommand runs a command with the given timeout and working directory.
// Returns stdout, stderr, and any error.
func runCommand(dir string, timeout time.Duration, name string, args ...string) (string, string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return stdout.String(), stderr.String(), fmt.Errorf("timeout after %s", timeout)
	}
	return stdout.String(), stderr.String(), err
}

const (
	// gitTimeout bounds local git operations (status, add, commit, rev-parse).
	gitTimeout = 30 * time.Second
	// gitNetTimeout bounds network git operations (fetch, push, pull, clone).
	// Generous for slow links and large repos; a huge submodule clone may
	// still exceed it.
	gitNetTimeout = 120 * time.Second
)

// runGitCore runs a git command in the given directory with the given
// timeout. On error, prefers stderr for the diagnostic detail but falls back
// to stdout — git commit, for example, writes "nothing to commit, working
// tree clean" to stdout, not stderr. When trim is false, stdout is returned
// untouched on success (error-path output is always trimmed).
func runGitCore(dir string, timeout time.Duration, trim bool, args ...string) (string, error) {
	stdout, stderr, err := runCommand(dir, timeout, "git", args...)
	if err != nil {
		details := strings.TrimSpace(stderr)
		if details == "" {
			details = strings.TrimSpace(stdout)
		}
		if details == "" {
			return strings.TrimSpace(stdout), err
		}
		return strings.TrimSpace(stdout), fmt.Errorf("%w: %s", err, details)
	}
	if trim {
		return strings.TrimSpace(stdout), nil
	}
	return stdout, nil
}

// runGit runs a local git command, returning trimmed stdout.
func runGit(dir string, args ...string) (string, error) {
	return runGitCore(dir, gitTimeout, true, args...)
}

// runGitNet runs a network git command (fetch/push/pull/clone) with a longer
// timeout, returning trimmed stdout.
func runGitNet(dir string, args ...string) (string, error) {
	return runGitCore(dir, gitNetTimeout, true, args...)
}

// runGitRaw is runGit without trimming stdout on success. Required for
// column-sensitive output like `git status --porcelain`, where the first
// character of the first line may be a meaningful space — trimming it shifts
// the status columns and corrupts the parsed path.
func runGitRaw(dir string, args ...string) (string, error) {
	return runGitCore(dir, gitTimeout, false, args...)
}

// expandCommaList splits comma-separated values within a flag list, so both
// `-f a -f b` and `-f "a,b"` are accepted.
func expandCommaList(items []string) []string {
	var expanded []string
	for _, item := range items {
		for _, part := range strings.Split(item, ",") {
			part = strings.TrimSpace(part)
			if part != "" {
				expanded = append(expanded, part)
			}
		}
	}
	return expanded
}

// parseFilter splits a comma-separated filter string into a slice.
func parseFilter(filter string) []string {
	if filter == "" {
		return nil
	}
	parts := strings.Split(filter, ",")
	var result []string
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			result = append(result, p)
		}
	}
	return result
}

// filterSubmodulePaths filters string paths by substring match (same logic as discoverPackages)
func filterSubmodulePaths(paths []string, filters []string) []string {
	if len(filters) == 0 {
		return paths
	}
	var filtered []string
	for _, p := range paths {
		for _, f := range filters {
			if strings.Contains(p, f) {
				filtered = append(filtered, p)
				break
			}
		}
	}
	return filtered
}

// filterGitSubmodules filters GitSubmoduleStatus slices by substring match on Path
func filterGitSubmodules(subs []GitSubmoduleStatus, filters []string) []GitSubmoduleStatus {
	if len(filters) == 0 {
		return subs
	}
	var filtered []GitSubmoduleStatus
	for _, sub := range subs {
		for _, f := range filters {
			if strings.Contains(sub.Path, f) {
				filtered = append(filtered, sub)
				break
			}
		}
	}
	return filtered
}

// filterGitSubmodulesWithParent applies submodule filtering with "." parent
// semantics and warns on unmatched tokens. The parent repo status is always
// present in GitOutput, so this only governs the submodule slice: "." alone
// (or any filter matching no submodule) yields an empty slice. With no filter
// the input is returned unchanged.
func filterGitSubmodulesWithParent(subs []GitSubmoduleStatus, filters []string) []GitSubmoduleStatus {
	_, subFilters := splitParentFilter(filters)
	warnUnmatchedFilters(subFilters, submodulePathsOf(subs), "submodule")
	if len(filters) > 0 && len(subFilters) == 0 {
		return []GitSubmoduleStatus{} // "." alone: parent only, no submodules
	}
	return filterGitSubmodules(subs, subFilters)
}

// splitParentFilter separates the "." token (the parent repo) from submodule
// filter tokens. Callers must distinguish "no filter at all" (len(filters)==0:
// everything) from "filter was . only" (len(filters)>0 && len(subFilters)==0:
// parent only, no submodules).
func splitParentFilter(filters []string) (includeParent bool, subFilters []string) {
	for _, f := range filters {
		if f == "." {
			includeParent = true
			continue
		}
		subFilters = append(subFilters, f)
	}
	return includeParent, subFilters
}

// unmatchedFilters returns filter tokens (excluding ".", the parent repo) that
// substring-match none of the given paths. Pure.
func unmatchedFilters(filters, paths []string) []string {
	var unmatched []string
	for _, f := range filters {
		if f == "." {
			continue
		}
		matched := false
		for _, p := range paths {
			if strings.Contains(p, f) {
				matched = true
				break
			}
		}
		if !matched {
			unmatched = append(unmatched, f)
		}
	}
	return unmatched
}

// warnUnmatchedFilters logs a stderr warning per filter token matching no path.
// noun is "submodule" or "package". Warning-only — does not affect exit codes.
func warnUnmatchedFilters(filters, paths []string, noun string) {
	for _, f := range unmatchedFilters(filters, paths) {
		logf("warning: filter %q matches no %s\n", f, noun)
	}
}

// submodulePathsOf extracts the Path field from each submodule status.
func submodulePathsOf(subs []GitSubmoduleStatus) []string {
	paths := make([]string, len(subs))
	for i, s := range subs {
		paths[i] = s.Path
	}
	return paths
}

// dedupeStrings returns items with duplicates removed, preserving first-seen order.
func dedupeStrings(items []string) []string {
	seen := make(map[string]bool, len(items))
	var result []string
	for _, item := range items {
		if seen[item] {
			continue
		}
		seen[item] = true
		result = append(result, item)
	}
	return result
}

// resolveSubmodulePath resolves a potentially short submodule name to the full path.
// Tries exact directory match first, then substring match against discovered submodules.
func resolveSubmodulePath(root, subPath string) (string, error) {
	// Exact match — directory exists
	exact := filepath.Join(root, subPath)
	if info, err := os.Stat(exact); err == nil && info.IsDir() {
		return subPath, nil
	}
	// Substring match against discovered submodules
	paths, err := getSubmodulePaths(root)
	if err != nil {
		return "", fmt.Errorf("submodule directory not found: %s", subPath)
	}
	var matches []string
	for _, p := range paths {
		if strings.Contains(p, subPath) {
			matches = append(matches, p)
		}
	}
	if len(matches) == 1 {
		progressf("resolved '%s' to '%s'\n", subPath, matches[0])
		return matches[0], nil
	}
	if len(matches) > 1 {
		return "", fmt.Errorf("ambiguous submodule path '%s' matches: %s", subPath, strings.Join(matches, ", "))
	}
	if len(paths) > 0 {
		return "", fmt.Errorf("submodule not found: '%s'. Available: %s", subPath, strings.Join(paths, ", "))
	}
	return "", fmt.Errorf("submodule directory not found: %s", subPath)
}

// resolveRoot converts a --path value to an absolute path.
func resolveRoot(path string) (string, error) {
	return filepath.Abs(path)
}
