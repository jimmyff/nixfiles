package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// nowTimestamp returns the current time as an RFC3339 string pointer.
func nowTimestamp() *string {
	t := time.Now().Format(time.RFC3339)
	return &t
}

// cacheDir returns the persistent cache directory for a given workspace root.
// Layout: ~/.cache/charm/cache/<safe-workspace-path>/
func cacheDir(root string) (string, error) {
	base, err := getSessionBase()
	if err != nil {
		return "", err
	}
	// Strip leading separator so path is "Users--jimmyff--..." not "--Users--..."
	cleaned := strings.TrimPrefix(root, string(filepath.Separator))
	return filepath.Join(base, "cache", safePath(cleaned)), nil
}

// writeCache atomically writes data as JSON to the cache directory for root.
// Fire-and-forget: logs warnings to stderr, never fails the calling command.
func writeCache(root, name string, data interface{}) {
	dir, err := cacheDir(root)
	if err != nil {
		logf("  cache warning: %v\n", err)
		return
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		logf("  cache warning: mkdir %v\n", err)
		return
	}
	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		logf("  cache warning: marshal %v\n", err)
		return
	}
	// Atomic write: temp file + rename
	tmp, err := os.CreateTemp(dir, ".tmp-"+name+"-*")
	if err != nil {
		logf("  cache warning: temp file %v\n", err)
		return
	}
	tmpPath := tmp.Name()
	if _, err := tmp.Write(jsonData); err != nil {
		tmp.Close()
		os.Remove(tmpPath)
		logf("  cache warning: write %v\n", err)
		return
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpPath)
		logf("  cache warning: close %v\n", err)
		return
	}
	target := filepath.Join(dir, name)
	if err := os.Rename(tmpPath, target); err != nil {
		os.Remove(tmpPath)
		logf("  cache warning: rename %v\n", err)
		return
	}
}

// readCache reads a cached JSON file. Returns nil, nil if the file doesn't exist.
func readCache(root, name string) ([]byte, error) {
	dir, err := cacheDir(root)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read cache: %w", err)
	}
	return data, nil
}
