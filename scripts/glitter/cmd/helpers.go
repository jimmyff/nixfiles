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

// detectRunner checks if a package uses Flutter (has flutter_test dependency).
func detectRunner(root, pkgPath string) string {
	pubspec := filepath.Join(root, pkgPath, "pubspec.yaml")
	data, err := os.ReadFile(pubspec)
	if err != nil {
		return "dart"
	}
	if strings.Contains(string(data), "flutter_test:") {
		return "flutter"
	}
	return "dart"
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

// resolveRoot converts a --path value to an absolute path.
func resolveRoot(path string) (string, error) {
	return filepath.Abs(path)
}
