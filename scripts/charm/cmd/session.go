package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// getSessionBase returns the base directory for charm sessions.
// Uses $XDG_CACHE_HOME/charm/ if set, otherwise ~/.cache/charm/.
func getSessionBase() (string, error) {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("cannot determine home directory: %w", err)
		}
		base = filepath.Join(home, ".cache")
	}
	return filepath.Join(base, "charm"), nil
}

// createSession creates a new session directory and returns its absolute path.
func createSession() (string, error) {
	base, err := getSessionBase()
	if err != nil {
		return "", err
	}
	ts := time.Now().Format("20060102-150405")
	abs := filepath.Join(base, ts)
	if err := os.MkdirAll(abs, 0755); err != nil {
		return "", fmt.Errorf("create session dir: %w", err)
	}
	return abs, nil
}

// ensureSessionSubdir creates a subdirectory within the session dir.
func ensureSessionSubdir(session, subdir string) error {
	abs := filepath.Join(session, subdir)
	return os.MkdirAll(abs, 0755)
}
