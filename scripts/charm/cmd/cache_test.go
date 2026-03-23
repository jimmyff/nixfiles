package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCacheDir(t *testing.T) {
	dir, err := cacheDir("/Users/jimmyff/workspace")
	if err != nil {
		t.Fatalf("cacheDir: %v", err)
	}
	// Should not have leading "--" from the path separator
	if strings.Contains(dir, "--Users") && strings.Contains(dir, "---") {
		t.Errorf("cacheDir produced double leading separator: %s", dir)
	}
	// Should contain the safe path
	if !strings.Contains(dir, "Users--jimmyff--workspace") {
		t.Errorf("cacheDir missing expected safe path segment: %s", dir)
	}
	// Should be under cache/ subdir
	if !strings.Contains(dir, filepath.Join("charm", "cache")) {
		t.Errorf("cacheDir not under charm/cache: %s", dir)
	}
}

func TestWriteReadCacheRoundTrip(t *testing.T) {
	tmpDir := t.TempDir()
	// Override XDG_CACHE_HOME so cache goes into our temp dir
	old := os.Getenv("XDG_CACHE_HOME")
	os.Setenv("XDG_CACHE_HOME", tmpDir)
	defer os.Setenv("XDG_CACHE_HOME", old)

	root := "/test/workspace"
	data := map[string]string{"hello": "world"}
	writeCache(root, "test.json", data)

	got, err := readCache(root, "test.json")
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

	root := "/test/json-valid"
	out := GitOutput{
		Timestamp:  nowTimestamp(),
		Repo:       GitRepoStatus{Path: ".", Branch: "main"},
		Submodules: []GitSubmoduleStatus{},
	}
	writeCache(root, "git.json", out)

	data, err := readCache(root, "git.json")
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
