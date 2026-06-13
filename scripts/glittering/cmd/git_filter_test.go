package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// diffRepoPaths runs GitDiff with the given args and returns the repo paths in
// its output. createSession writes patch files under $XDG_CACHE_HOME, so the
// caller must redirect it to a temp dir.
func diffRepoPaths(t *testing.T, args []string) []string {
	t.Helper()
	var out DiffOutput
	stdout := captureStdout(t, func() {
		if got := GitDiff(args); got != ExitOK {
			t.Fatalf("GitDiff %v: expected ExitOK, got %d", args, got)
		}
	})
	if err := json.Unmarshal([]byte(stdout), &out); err != nil {
		t.Fatalf("GitDiff output not valid JSON: %v\n%s", err, stdout)
	}
	paths := make([]string, len(out.Repos))
	for i, r := range out.Repos {
		paths[i] = r.Path
	}
	return paths
}

func contains(paths []string, want string) bool {
	for _, p := range paths {
		if p == want {
			return true
		}
	}
	return false
}

// "." in --filter selects the parent repo for git diff; submodule tokens select
// submodules; both together select both. (Before the fix "." matched nothing.)
func TestGitDiff_FilterDot(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	parent := setupWorkspaceWithRemote(t)

	if err := os.WriteFile(filepath.Join(parent, "PROJECT_PLAN.md"), []byte("plan v2\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := os.WriteFile(filepath.Join(parent, "sub", "feature.txt"), []byte("new\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}

	dotOnly := diffRepoPaths(t, []string{"--path", parent, "--filter", "."})
	if len(dotOnly) != 1 || dotOnly[0] != "." {
		t.Errorf("--filter .: expected [.], got %v", dotOnly)
	}

	subOnly := diffRepoPaths(t, []string{"--path", parent, "--filter", "sub"})
	if len(subOnly) != 1 || subOnly[0] != "sub" {
		t.Errorf("--filter sub: expected [sub], got %v", subOnly)
	}

	both := diffRepoPaths(t, []string{"--path", parent, "--filter", ".,sub"})
	if len(both) != 2 || !contains(both, ".") || !contains(both, "sub") {
		t.Errorf("--filter .,sub: expected [. sub], got %v", both)
	}
}

// git status with --filter . keeps the parent repo row and empties submodules.
func TestGitStatus_FilterDot(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)

	var out GitOutput
	stdout := captureStdout(t, func() {
		if got := gitStatus([]string{"--path", parent, "--skip-fetch", "--filter", "."}); got != ExitOK {
			t.Fatalf("gitStatus: expected ExitOK, got %d", got)
		}
	})
	if err := json.Unmarshal([]byte(stdout), &out); err != nil {
		t.Fatalf("status output not valid JSON: %v\n%s", err, stdout)
	}
	if out.Repo.Branch == "" {
		t.Errorf("expected parent repo row present, got: %s", stdout)
	}
	if len(out.Submodules) != 0 {
		t.Errorf("--filter .: expected no submodules, got %v", out.Submodules)
	}
}

// git check with --filter . checks the parent only — a submodule-only issue
// must not affect the verdict. A stash is used because it leaves the parent
// working tree clean (HEAD and gitlink content unchanged), unlike a dirty
// working file which would also mark the parent dirty.
func TestGitCheck_FilterDot_ChecksParentOnly(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)

	subDir := filepath.Join(parent, "sub")
	if err := os.WriteFile(filepath.Join(subDir, "wip.txt"), []byte("wip\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	gitRun(t, subDir, "stash", "-u")

	var out CheckOutput
	var got int
	stdout := captureStdout(t, func() {
		got = GitCheck([]string{"--path", parent, "--skip-fetch", "--filter", "."})
	})
	if got != ExitOK {
		t.Fatalf("GitCheck --filter .: expected ExitOK (parent clean, sub excluded), got %d: %s", got, stdout)
	}
	if err := json.Unmarshal([]byte(stdout), &out); err != nil {
		t.Fatalf("check output not valid JSON: %v\n%s", err, stdout)
	}
	if !out.Clean {
		t.Errorf("--filter . with clean parent: expected clean=true, got: %s", stdout)
	}

	// Sanity: without the filter the stash surfaces as a submodule issue.
	var unfiltered CheckOutput
	stdout = captureStdout(t, func() {
		GitCheck([]string{"--path", parent, "--skip-fetch"})
	})
	if err := json.Unmarshal([]byte(stdout), &unfiltered); err != nil {
		t.Fatalf("check output not valid JSON: %v\n%s", err, stdout)
	}
	foundSubStash := false
	for _, issue := range unfiltered.Issues {
		if issue.Repo == "sub" && issue.Type == "stash" {
			foundSubStash = true
		}
	}
	if !foundSubStash {
		t.Errorf("unfiltered check should report the submodule stash, got: %s", stdout)
	}
}

// Filtered push/pull operate on submodules; "." (the parent) is rejected before
// any network operation.
func TestGitPush_FilterDotRejected(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	if got := GitPush([]string{"--path", parent, "--filter", "."}); got != ExitUsage {
		t.Errorf("git push --filter .: expected ExitUsage, got %d", got)
	}
}

func TestGitPull_FilterDotRejected(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	before := gitOut(t, parent, "rev-parse", "HEAD")
	if got := GitPull([]string{"--path", parent, "--filter", "."}); got != ExitUsage {
		t.Errorf("git pull --filter .: expected ExitUsage, got %d", got)
	}
	// Rejection happens before the parent pull, so HEAD is untouched.
	if after := gitOut(t, parent, "rev-parse", "HEAD"); before != after {
		t.Errorf("parent HEAD changed despite rejected pull: before %s after %s", before, after)
	}
}
