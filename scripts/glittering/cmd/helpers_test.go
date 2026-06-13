package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Regression: git commit on a clean repo writes "nothing to commit, working
// tree clean" to stdout (not stderr). runGit used to drop stdout on error,
// leaving callers with an empty diagnostic. Now it falls back to stdout.
func TestRunGit_FallsBackToStdoutOnEmptyStderr(t *testing.T) {
	tmp := t.TempDir()
	for _, args := range [][]string{
		{"init", "--quiet", "--initial-branch=main"},
		{"config", "user.email", "test@example.com"},
		{"config", "user.name", "test"},
		{"commit", "--quiet", "--allow-empty", "-m", "init"},
	} {
		cmd := exec.Command("git", args...)
		cmd.Dir = tmp
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v failed: %v: %s", args, err, out)
		}
	}

	_, err := runGit(tmp, "commit", "-m", "test")
	if err == nil {
		t.Fatal("expected commit on clean repo to fail")
	}
	if !strings.Contains(err.Error(), "nothing to commit") {
		t.Errorf("expected error to surface stdout 'nothing to commit', got: %q", err.Error())
	}
}

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

func TestSafePath_Parent(t *testing.T) {
	if got := safePath("."); got != "_parent" {
		t.Errorf("safePath(\".\"): expected _parent (not a hidden ..-like name), got %q", got)
	}
}

func TestSafePath_NestedPath(t *testing.T) {
	if got := safePath("packages/foo"); got != "packages--foo" {
		t.Errorf("safePath: expected packages--foo, got %q", got)
	}
}

func TestSplitParentFilter_Nil(t *testing.T) {
	includeParent, subFilters := splitParentFilter(nil)
	if includeParent || len(subFilters) != 0 {
		t.Errorf("nil: expected (false, []), got (%v, %v)", includeParent, subFilters)
	}
}

func TestSplitParentFilter_NoDot(t *testing.T) {
	includeParent, subFilters := splitParentFilter([]string{"foo", "bar"})
	if includeParent {
		t.Errorf("no dot: expected includeParent=false")
	}
	if len(subFilters) != 2 || subFilters[0] != "foo" || subFilters[1] != "bar" {
		t.Errorf("no dot: expected [foo bar], got %v", subFilters)
	}
}

func TestSplitParentFilter_DotOnly(t *testing.T) {
	includeParent, subFilters := splitParentFilter([]string{"."})
	if !includeParent {
		t.Errorf("dot only: expected includeParent=true")
	}
	if len(subFilters) != 0 {
		t.Errorf("dot only: expected no sub filters, got %v", subFilters)
	}
}

func TestSplitParentFilter_DotPlusSubs(t *testing.T) {
	includeParent, subFilters := splitParentFilter([]string{".", "foo"})
	if !includeParent || len(subFilters) != 1 || subFilters[0] != "foo" {
		t.Errorf("dot+subs: expected (true, [foo]), got (%v, %v)", includeParent, subFilters)
	}
	// Order-independent: dot last
	includeParent, subFilters = splitParentFilter([]string{"foo", "."})
	if !includeParent || len(subFilters) != 1 || subFilters[0] != "foo" {
		t.Errorf("subs+dot: expected (true, [foo]), got (%v, %v)", includeParent, subFilters)
	}
}

func TestUnmatchedFilters_AllMatch(t *testing.T) {
	got := unmatchedFilters([]string{"foo", "bar"}, []string{"packages/foo", "packages/bar"})
	if len(got) != 0 {
		t.Errorf("all match: expected none, got %v", got)
	}
}

func TestUnmatchedFilters_SomeUnmatched(t *testing.T) {
	got := unmatchedFilters([]string{"foo", "xyz"}, []string{"packages/foo"})
	if len(got) != 1 || got[0] != "xyz" {
		t.Errorf("some unmatched: expected [xyz], got %v", got)
	}
}

func TestUnmatchedFilters_DotExcluded(t *testing.T) {
	// "." is the parent token, never reported as unmatched even with no paths.
	got := unmatchedFilters([]string{"."}, nil)
	if len(got) != 0 {
		t.Errorf("dot excluded: expected none, got %v", got)
	}
}

func TestUnmatchedFilters_EmptyInputs(t *testing.T) {
	if got := unmatchedFilters(nil, []string{"packages/foo"}); len(got) != 0 {
		t.Errorf("nil filters: expected none, got %v", got)
	}
	if got := unmatchedFilters([]string{"foo"}, nil); len(got) != 1 || got[0] != "foo" {
		t.Errorf("nil paths: expected [foo], got %v", got)
	}
}

func TestDedupeStrings_PreservesOrder(t *testing.T) {
	got := dedupeStrings([]string{"b", "a", "b", "c", "a"})
	want := []string{"b", "a", "c"}
	if len(got) != len(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("at %d: expected %q, got %q (full: %v)", i, want[i], got[i], got)
		}
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
