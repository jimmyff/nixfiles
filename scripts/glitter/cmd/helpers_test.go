package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFilterSubmodulePaths_NoFilters(t *testing.T) {
	paths := []string{"packages/foo", "packages/bar", "lib/baz"}
	got := filterSubmodulePaths(paths, nil)
	if len(got) != 3 {
		t.Errorf("no filters: expected 3 paths, got %d", len(got))
	}
}

func TestFilterSubmodulePaths_SingleFilter(t *testing.T) {
	paths := []string{"packages/foo", "packages/bar", "lib/baz"}
	got := filterSubmodulePaths(paths, []string{"foo"})
	if len(got) != 1 || got[0] != "packages/foo" {
		t.Errorf("single filter 'foo': expected [packages/foo], got %v", got)
	}
}

func TestFilterSubmodulePaths_MultipleFilters(t *testing.T) {
	paths := []string{"packages/foo", "packages/bar", "lib/baz"}
	got := filterSubmodulePaths(paths, []string{"foo", "baz"})
	if len(got) != 2 {
		t.Errorf("multiple filters: expected 2 paths, got %d: %v", len(got), got)
	}
}

func TestFilterSubmodulePaths_NoMatches(t *testing.T) {
	paths := []string{"packages/foo", "packages/bar"}
	got := filterSubmodulePaths(paths, []string{"xyz"})
	if len(got) != 0 {
		t.Errorf("no matches: expected 0 paths, got %d", len(got))
	}
}

func TestFilterGitSubmodules_NoFilters(t *testing.T) {
	subs := []GitSubmoduleStatus{
		{Path: "packages/foo"},
		{Path: "packages/bar"},
	}
	got := filterGitSubmodules(subs, nil)
	if len(got) != 2 {
		t.Errorf("no filters: expected 2, got %d", len(got))
	}
}

func TestFilterGitSubmodules_SingleFilter(t *testing.T) {
	subs := []GitSubmoduleStatus{
		{Path: "packages/foo"},
		{Path: "packages/bar"},
		{Path: "lib/baz"},
	}
	got := filterGitSubmodules(subs, []string{"bar"})
	if len(got) != 1 || got[0].Path != "packages/bar" {
		t.Errorf("single filter 'bar': expected [packages/bar], got %v", got)
	}
}

func TestFilterGitSubmodules_MultipleFilters(t *testing.T) {
	subs := []GitSubmoduleStatus{
		{Path: "packages/foo"},
		{Path: "packages/bar"},
		{Path: "lib/baz"},
	}
	got := filterGitSubmodules(subs, []string{"foo", "lib"})
	if len(got) != 2 {
		t.Errorf("multiple filters: expected 2, got %d: %v", len(got), got)
	}
}

func TestFilterGitSubmodules_NoMatches(t *testing.T) {
	subs := []GitSubmoduleStatus{
		{Path: "packages/foo"},
	}
	got := filterGitSubmodules(subs, []string{"xyz"})
	if len(got) != 0 {
		t.Errorf("no matches: expected 0, got %d", len(got))
	}
}

func TestFilterSubmodulePaths_NilPaths(t *testing.T) {
	got := filterSubmodulePaths(nil, []string{"foo"})
	if len(got) != 0 {
		t.Errorf("nil paths: expected 0, got %d", len(got))
	}
}

func TestFilterGitSubmodules_NilSubs(t *testing.T) {
	got := filterGitSubmodules(nil, []string{"foo"})
	if len(got) != 0 {
		t.Errorf("nil subs: expected 0, got %d", len(got))
	}
}

func TestResolveRoot_Dot(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get cwd: %v", err)
	}
	got, err := resolveRoot(".")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != cwd {
		t.Errorf("resolveRoot('.'): expected %s, got %s", cwd, got)
	}
	if !filepath.IsAbs(got) {
		t.Errorf("resolveRoot('.'): expected absolute path, got %s", got)
	}
}

func TestResolveRoot_RelativePath(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get cwd: %v", err)
	}
	got, err := resolveRoot("foo/bar")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	expected := filepath.Join(cwd, "foo/bar")
	if got != expected {
		t.Errorf("resolveRoot('foo/bar'): expected %s, got %s", expected, got)
	}
}

func TestResolveRoot_AbsolutePassthrough(t *testing.T) {
	abs := filepath.Join(os.TempDir(), "workspace")
	got, err := resolveRoot(abs)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != abs {
		t.Errorf("resolveRoot(%s): expected same path back, got %s", abs, got)
	}
}

func TestResolveSubmodulePath_ExactMatch(t *testing.T) {
	tmp := t.TempDir()
	os.MkdirAll(filepath.Join(tmp, "packages", "foo"), 0755)

	got, err := resolveSubmodulePath(tmp, "packages/foo")
	if err != nil {
		t.Fatalf("exact match: unexpected error: %v", err)
	}
	if got != "packages/foo" {
		t.Errorf("exact match: expected 'packages/foo', got '%s'", got)
	}
}

func TestResolveSubmodulePath_NoMatch(t *testing.T) {
	tmp := t.TempDir()
	_, err := resolveSubmodulePath(tmp, "nonexistent")
	if err == nil {
		t.Error("no match: expected error, got nil")
	}
}

func TestResolveSubmodulePath_FileNotDir(t *testing.T) {
	tmp := t.TempDir()
	// Create a file (not a directory) — should not match as exact
	os.WriteFile(filepath.Join(tmp, "notadir"), []byte("x"), 0644)
	_, err := resolveSubmodulePath(tmp, "notadir")
	if err == nil {
		t.Error("file not dir: expected error, got nil")
	}
}
