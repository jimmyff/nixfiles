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

// cachePath returns the cache file path for a given absolute directory and filename.
// Layout: ~/.cache/charm/cache/<absDir-without-leading-sep>/filename
func cachePath(absDir, filename string) (string, error) {
	base, err := getSessionBase()
	if err != nil {
		return "", err
	}
	trimmed := strings.TrimPrefix(absDir, string(filepath.Separator))
	return filepath.Join(base, "cache", trimmed, filename), nil
}

// writeCache atomically writes data as JSON to the per-package cache path.
// Fire-and-forget: logs warnings to stderr, never fails the calling command.
func writeCache(absDir, filename string, data interface{}) {
	path, err := cachePath(absDir, filename)
	if err != nil {
		logf("  cache warning: %v\n", err)
		return
	}
	dir := filepath.Dir(path)
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
	tmp, err := os.CreateTemp(dir, ".tmp-"+filename+"-*")
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
	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath)
		logf("  cache warning: rename %v\n", err)
		return
	}
}

// readCache reads a cached JSON file. Returns nil, nil if the file doesn't exist.
func readCache(absDir, filename string) ([]byte, error) {
	path, err := cachePath(absDir, filename)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read cache: %w", err)
	}
	return data, nil
}

// readCacheTree walks the cache tree under rootAbsDir and returns all files
// matching filename, keyed by their relative package path from the root.
// Returns empty map (not error) if root doesn't exist.
func readCacheTree(rootAbsDir, filename string) (map[string][]byte, error) {
	rootPath, err := cachePath(rootAbsDir, "")
	if err != nil {
		return nil, err
	}
	result := make(map[string][]byte)
	if _, err := os.Stat(rootPath); os.IsNotExist(err) {
		return result, nil
	}
	err = filepath.Walk(rootPath, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || info.Name() != filename {
			return nil
		}
		parentDir := filepath.Dir(path)
		relPath, err := filepath.Rel(rootPath, parentDir)
		if err != nil {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		result[relPath] = data
		return nil
	})
	if err != nil {
		return nil, err
	}
	return result, nil
}
