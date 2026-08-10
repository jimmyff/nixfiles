package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// runSync runs GitSync capturing its JSON output.
func runSync(t *testing.T, args ...string) (int, GitSyncOutput) {
	t.Helper()
	var code int
	stdout := captureStdout(t, func() { code = GitSync(args) })
	var out GitSyncOutput
	if err := json.Unmarshal([]byte(stdout), &out); err != nil {
		t.Fatalf("output is not valid JSON: %v\noutput: %s", err, stdout)
	}
	return code, out
}

// advanceSubAndPin commits a new file in sub, pushes it, and bumps the parent
// pin to it — the state a parent-side merge/pull produces. Returns the new pin.
func advanceSubAndPin(t *testing.T, parent string) string {
	t.Helper()
	sub := filepath.Join(parent, "sub")
	if err := os.WriteFile(filepath.Join(sub, "b.txt"), []byte("b\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	gitRun(t, sub, "add", "b.txt")
	gitRun(t, sub, "commit", "--quiet", "-m", "B")
	gitRun(t, sub, "push", "--quiet", "origin", "main")
	gitRun(t, parent, "add", "sub")
	gitRun(t, parent, "commit", "--quiet", "-m", "bump sub")
	return strings.TrimSpace(gitOut(t, sub, "rev-parse", "HEAD"))
}

func subHead(t *testing.T, parent string) string {
	t.Helper()
	return strings.TrimSpace(gitOut(t, filepath.Join(parent, "sub"), "rev-parse", "HEAD"))
}

func subBranch(t *testing.T, parent string) string {
	t.Helper()
	return strings.TrimSpace(gitOut(t, filepath.Join(parent, "sub"), "branch", "--show-current"))
}

func TestGitSync_InSync(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	code, out := runSync(t, "--path", parent, "--skip-fetch")
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if len(out.Submodules) != 1 || out.Submodules[0].Action != "in_sync" {
		t.Errorf("expected in_sync, got %+v", out.Submodules)
	}
}

// Regression for the reported incident: a parent merge moves the gitlink
// forward but the submodule worktree stays behind. Sync must fast-forward the
// tracked branch to the pin — on-branch, not detached, not past the pin.
func TestGitSync_BehindPin_FastForwardsOnBranch(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	pin := advanceSubAndPin(t, parent)
	sub := filepath.Join(parent, "sub")
	gitRun(t, sub, "reset", "--hard", "--quiet", "HEAD~1")
	if subHead(t, parent) == pin {
		t.Fatal("fixture: worktree should be behind the pin")
	}

	code, out := runSync(t, "--path", parent, "--skip-fetch")
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	res := out.Submodules[0]
	if res.Action != "synced" || res.ToRef != pin || res.NewCommits != 1 {
		t.Errorf("expected synced to %s (1 commit), got %+v", pin, res)
	}
	if got := subHead(t, parent); got != pin {
		t.Errorf("worktree HEAD: expected pin %s, got %s", pin, got)
	}
	if got := subBranch(t, parent); got != "main" {
		t.Errorf("submodule must stay on its branch, got %q (detached?)", got)
	}
}

// Forward-only: a worktree ahead of the pin is the `commit --parent-only`
// flow's job — sync must not rewind it.
func TestGitSync_Ahead_Untouched(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	sub := filepath.Join(parent, "sub")
	if err := os.WriteFile(filepath.Join(sub, "wip.txt"), []byte("wip\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	gitRun(t, sub, "add", "wip.txt")
	gitRun(t, sub, "commit", "--quiet", "-m", "wip")
	before := subHead(t, parent)

	code, out := runSync(t, "--path", parent, "--skip-fetch")
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	res := out.Submodules[0]
	if res.Action != "ahead" || !strings.Contains(res.Hint, "--parent-only") {
		t.Errorf("expected ahead with --parent-only hint, got %+v", res)
	}
	if got := subHead(t, parent); got != before {
		t.Errorf("worktree must be untouched, moved %s -> %s", before, got)
	}
}

func TestGitSync_Diverged_ErrorsAndLeavesWorktree(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	advanceSubAndPin(t, parent)
	sub := filepath.Join(parent, "sub")
	gitRun(t, sub, "reset", "--hard", "--quiet", "HEAD~1")
	if err := os.WriteFile(filepath.Join(sub, "c.txt"), []byte("c\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	gitRun(t, sub, "add", "c.txt")
	gitRun(t, sub, "commit", "--quiet", "-m", "C")
	before := subHead(t, parent)

	code, out := runSync(t, "--path", parent, "--skip-fetch")
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure on divergence, got %d: %+v", code, out)
	}
	res := out.Submodules[0]
	if res.Action != "diverged" || !strings.Contains(res.Error, "diverged") {
		t.Errorf("expected diverged, got %+v", res)
	}
	if got := subHead(t, parent); got != before {
		t.Errorf("diverged worktree must be untouched, moved %s -> %s", before, got)
	}
	if got := subBranch(t, parent); got != "main" {
		t.Errorf("submodule must stay on its branch, got %q", got)
	}
}

func TestGitSync_DirtySkipped(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	advanceSubAndPin(t, parent)
	sub := filepath.Join(parent, "sub")
	gitRun(t, sub, "reset", "--hard", "--quiet", "HEAD~1")
	if err := os.WriteFile(filepath.Join(sub, "junk.txt"), []byte("junk\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	before := subHead(t, parent)

	code, out := runSync(t, "--path", parent, "--skip-fetch")
	if code != ExitOK {
		t.Fatalf("expected ExitOK (skip is a warning), got %d: %+v", code, out)
	}
	res := out.Submodules[0]
	if res.Action != "skipped_dirty" {
		t.Errorf("expected skipped_dirty, got %+v", res)
	}
	if len(out.Warnings) != 1 {
		t.Errorf("expected 1 warning, got %v", out.Warnings)
	}
	if got := subHead(t, parent); got != before {
		t.Errorf("dirty worktree must be untouched, moved %s -> %s", before, got)
	}
}

// A detached submodule behind the pin (e.g. after `git submodule update`)
// reattaches to the pin's branch, landing exactly on the pin.
func TestGitSync_DetachedBehindPin_Reattaches(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	pin := advanceSubAndPin(t, parent)
	sub := filepath.Join(parent, "sub")
	gitRun(t, sub, "checkout", "--quiet", "--detach", "HEAD~1")

	code, out := runSync(t, "--path", parent, "--skip-fetch")
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	res := out.Submodules[0]
	if res.Action != "reattached" || res.Branch != "main" || res.ToRef != pin || res.NewCommits != 1 {
		t.Errorf("expected reattached to main at %s (1 commit), got %+v", pin, res)
	}
	if got := subHead(t, parent); got != pin {
		t.Errorf("worktree HEAD: expected pin %s, got %s", pin, got)
	}
	if got := subBranch(t, parent); got != "main" {
		t.Errorf("expected reattached to main, got %q", got)
	}
}

// Reattaching must never overshoot: when the local branch is ahead of the pin,
// checking it out would move the worktree past the pinned state — refuse.
func TestGitSync_DetachedBranchAheadOfPin_Refuses(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)
	sub := filepath.Join(parent, "sub")
	pin := subHead(t, parent)
	if err := os.WriteFile(filepath.Join(sub, "b.txt"), []byte("b\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	gitRun(t, sub, "add", "b.txt")
	gitRun(t, sub, "commit", "--quiet", "-m", "B") // main now ahead of pin
	gitRun(t, sub, "checkout", "--quiet", "--detach", pin)

	code, out := runSync(t, "--path", parent, "--skip-fetch")
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
	}
	res := out.Submodules[0]
	if res.Action != "error" || !strings.Contains(res.Error, "ahead of pinned ref") {
		t.Errorf("expected refusal with 'ahead of pinned ref', got %+v", res)
	}
	if got := subHead(t, parent); got != pin {
		t.Errorf("worktree must be untouched, moved to %s", got)
	}
}

func TestGitSync_ParentFilterRejected(t *testing.T) {
	got := GitSync([]string{"--filter", ".", "--path", t.TempDir()})
	if got != ExitUsage {
		t.Errorf("--filter .: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}
