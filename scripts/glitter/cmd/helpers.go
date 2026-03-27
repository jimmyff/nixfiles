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
func safePath(p string) string {
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

// runGit runs a git command in the given directory.
func runGit(dir string, args ...string) (string, error) {
	stdout, stderr, err := runCommand(dir, 30*time.Second, "git", args...)
	if err != nil {
		return strings.TrimSpace(stdout), fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr))
	}
	return strings.TrimSpace(stdout), nil
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
