package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestCachePath(t *testing.T) {
	path, err := cachePath("/Users/jimmyff/project", "test.json")
	if err != nil {
		t.Fatalf("cachePath: %v", err)
	}
	// Should contain the mirrored filesystem path
	if !filepath.IsAbs(path) {
		t.Errorf("cachePath should return absolute path, got: %s", path)
	}
	expected := filepath.Join("cache", "Users", "jimmyff", "project", "test.json")
	if !containsPath(path, expected) {
		t.Errorf("cachePath missing expected path segment %q in: %s", expected, path)
	}
}

func TestWriteReadCacheRoundTrip(t *testing.T) {
	tmpDir := t.TempDir()
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	absDir := "/test/workspace"
	data := map[string]string{"hello": "world"}
	writeCache(absDir, "test.json", data)

	got, err := readCache(absDir, "test.json")
	if err != nil {
		t.Fatalf("readCache: %v", err)
	}
	if got == nil {
		t.Fatal("readCache returned nil for existing cache")
	}

	var parsed map[string]string
	if err := json.Unmarshal(got, &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if parsed["hello"] != "world" {
		t.Errorf("expected world, got %s", parsed["hello"])
	}
}

func TestReadCacheNonExistent(t *testing.T) {
	tmpDir := t.TempDir()
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	got, err := readCache("/nonexistent/path", "missing.json")
	if err != nil {
		t.Fatalf("readCache: %v", err)
	}
	if got != nil {
		t.Errorf("expected nil for non-existent cache, got %s", string(got))
	}
}

func TestWriteCacheProducesValidJSON(t *testing.T) {
	tmpDir := t.TempDir()
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	absDir := "/test/json-valid"
	out := GitOutput{
		Timestamp:  nowTimestamp(),
		Repo:       GitRepoStatus{Path: ".", Branch: "main"},
		Submodules: []GitSubmoduleStatus{},
	}
	writeCache(absDir, "git.json", out)

	data, err := readCache(absDir, "git.json")
	if err != nil {
		t.Fatalf("readCache: %v", err)
	}
	if data == nil {
		t.Fatal("cache file not written")
	}

	var parsed GitOutput
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("invalid JSON in cache: %v", err)
	}
	if parsed.Timestamp == nil {
		t.Error("expected non-nil timestamp")
	}
	if parsed.Repo.Branch != "main" {
		t.Errorf("expected branch main, got %s", parsed.Repo.Branch)
	}
}

func TestNowTimestamp(t *testing.T) {
	ts := nowTimestamp()
	if ts == nil {
		t.Fatal("nowTimestamp returned nil")
	}
	if *ts == "" {
		t.Fatal("nowTimestamp returned empty string")
	}
}

func TestReadCacheTree(t *testing.T) {
	tmpDir := t.TempDir()
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	root := "/test/project"
	// Write 3 per-package results
	pkgs := []struct {
		absDir string
		data   TestPackageResult
	}{
		{filepath.Join(root, "apps/notes"), TestPackageResult{Status: "pass", Total: 10, Passed: 10}},
		{filepath.Join(root, "apps/calendar"), TestPackageResult{Status: "fail", Total: 5, Failed: 2}},
		{filepath.Join(root, "packages/core"), TestPackageResult{Status: "pass", Total: 3, Passed: 3}},
	}
	for _, pkg := range pkgs {
		writeCache(pkg.absDir, "test.json", pkg.data)
	}

	entries, err := readCacheTree(root, "test.json")
	if err != nil {
		t.Fatalf("readCacheTree: %v", err)
	}
	if len(entries) != 3 {
		t.Fatalf("expected 3 entries, got %d", len(entries))
	}

	// Verify relative paths
	expectedPaths := map[string]bool{
		"apps/notes":    true,
		"apps/calendar": true,
		"packages/core": true,
	}
	for relPath := range entries {
		if !expectedPaths[relPath] {
			t.Errorf("unexpected relative path: %s", relPath)
		}
	}

	// Verify data round-trips
	var result TestPackageResult
	if err := json.Unmarshal(entries["apps/notes"], &result); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if result.Status != "pass" || result.Total != 10 {
		t.Errorf("unexpected result for apps/notes: %+v", result)
	}
}

func TestReadCacheTreeEmpty(t *testing.T) {
	tmpDir := t.TempDir()
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	entries, err := readCacheTree("/nonexistent/root", "test.json")
	if err != nil {
		t.Fatalf("readCacheTree: %v", err)
	}
	if len(entries) != 0 {
		t.Errorf("expected empty map, got %d entries", len(entries))
	}
}

func TestReadCacheTreeIgnoresOtherFiles(t *testing.T) {
	tmpDir := t.TempDir()
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	root := "/test/project"
	pkgDir := filepath.Join(root, "apps/notes")

	writeCache(pkgDir, "test.json", TestPackageResult{Status: "pass"})
	writeCache(pkgDir, "analyze.json", AnalyzePackageResult{Status: "pass"})

	entries, err := readCacheTree(root, "test.json")
	if err != nil {
		t.Fatalf("readCacheTree: %v", err)
	}
	if len(entries) != 1 {
		t.Errorf("expected 1 entry (test.json only), got %d", len(entries))
	}
	if _, ok := entries["apps/notes"]; !ok {
		t.Error("expected apps/notes entry")
	}
}

func TestSamePackageDifferentRoots(t *testing.T) {
	tmpDir := t.TempDir()
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	// Same absolute package path, regardless of how it's constructed
	absPath := "/test/project/apps/notes"

	writeCache(absPath, "test.json", TestPackageResult{Status: "pass", Total: 5})

	// Read it back — should find the same file
	data, err := readCache(absPath, "test.json")
	if err != nil {
		t.Fatalf("readCache: %v", err)
	}
	if data == nil {
		t.Fatal("expected cache data")
	}

	// Verify the cache path is deterministic for the same absPath
	path1, _ := cachePath(absPath, "test.json")
	path2, _ := cachePath(absPath, "test.json")
	if path1 != path2 {
		t.Errorf("cachePath not deterministic: %s vs %s", path1, path2)
	}
}

// containsPath checks if full contains the expected path segment.
func containsPath(full, expected string) bool {
	// Normalize separators for comparison
	return len(full) > len(expected) &&
		full[len(full)-len(expected):] == expected ||
		indexOf(full, expected) >= 0
}

func indexOf(s, sub string) int {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
