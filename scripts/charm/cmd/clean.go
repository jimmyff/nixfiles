package cmd

import (
	"flag"
	"os"
	"path/filepath"
	"time"
)

// Clean removes session directories older than 24 hours.
func Clean(args []string) int {
	fs := flag.NewFlagSet("clean", flag.ExitOnError)
	fs.Parse(args)

	sessionBase, err := getSessionBase()
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	entries, err := os.ReadDir(sessionBase)
	if err != nil {
		if os.IsNotExist(err) {
			logf("charm: no sessions to clean\n")
			return ExitOK
		}
		logf("error: %v\n", err)
		return ExitFailure
	}

	cutoff := time.Now().Add(-24 * time.Hour)
	removed := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if entry.Name() == "cache" {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) {
			sessionPath := filepath.Join(sessionBase, entry.Name())
			if err := os.RemoveAll(sessionPath); err != nil {
				logf("  warning: failed to remove %s: %v\n", entry.Name(), err)
			} else {
				removed++
			}
		}
	}

	logf("charm: removed %d old sessions\n", removed)

	// Remove charm cache dir if empty
	remaining, _ := os.ReadDir(sessionBase)
	if len(remaining) == 0 {
		os.Remove(sessionBase)
	}

	return ExitOK
}
