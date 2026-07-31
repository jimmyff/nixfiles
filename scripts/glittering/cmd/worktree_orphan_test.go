package cmd

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

// makeOrphan fabricates the bug state deterministically: move the worktree
// aside, prune its admin entry (--expire=now — the default gc.worktreePruneExpire
// keeps missing-but-recent worktrees for 3 months), move it back. Result:
// directory on disk, unknown to git — exactly what a failed removal leaves.
func makeOrphan(t *testing.T, proj, name string) string {
	t.Helper()
	path := filepath.Join(proj, name)
	bak := path + ".bak"
	if err := os.Rename(path, bak); err != nil {
		t.Fatalf("move worktree aside: %v", err)
	}
	gitRun(t, filepath.Join(proj, ".bare"), "worktree", "prune", "--expire=now")
	if err := os.Rename(bak, path); err != nil {
		t.Fatalf("restore worktree: %v", err)
	}
	return path
}

// --- pure ---

func TestIsRetryableRemoveErr(t *testing.T) {
	pathErr := func(errno syscall.Errno) error {
		return &fs.PathError{Op: "rmdir", Path: "x", Err: errno}
	}
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"ENOTEMPTY", pathErr(syscall.ENOTEMPTY), true},
		{"EEXIST", pathErr(syscall.EEXIST), true},
		{"EACCES", pathErr(syscall.EACCES), false},
		{"wrapped ENOTEMPTY", fmt.Errorf("wrap: %w", pathErr(syscall.ENOTEMPTY)), true},
		{"plain error", errors.New("x"), false},
		{"nil", nil, false},
	}
	for _, c := range cases {
		if got := isRetryableRemoveErr(c.err); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestRemoveDirRetryGuards(t *testing.T) {
	for _, bad := range []string{"", "/", "relative/path"} {
		if err := removeDirRetry(bad); err == nil {
			t.Errorf("removeDirRetry(%q) should refuse", bad)
		}
	}
	// A missing absolute path is success (RemoveAll semantics) — a manually
	// deleted but still-registered worktree removes cleanly.
	if err := removeDirRetry(filepath.Join(t.TempDir(), "missing")); err != nil {
		t.Errorf("missing path should be nil, got %v", err)
	}
}

// --- fallback wiring ---

// git fails on an unregistered dir; the fallback must delete it and its cache.
func TestRemoveWorktreeDirFallback(t *testing.T) {
	proj := setupWorktreeProject(t)
	stray := filepath.Join(proj, "stray")
	if err := os.MkdirAll(stray, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stray, "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	writeCache(stray, "test.json", map[string]string{"k": "v"})

	if err := removeWorktreeDir(filepath.Join(proj, ".bare"), stray); err != nil {
		t.Fatalf("fallback removal failed: %v", err)
	}
	if _, err := os.Stat(stray); err == nil {
		t.Error("stray dir should be gone")
	}
	if p, _ := cachePath(stray, ""); p != "" {
		if _, err := os.Stat(p); err == nil {
			t.Error("stray cache tree should be deleted")
		}
	}
}

// --- orphan remove ---

// The main regression: a deregistered-but-present directory must be visible
// to remove (not "no worktree named"), gated behind --force, and reaped with
// its cache.
func TestWorktreeRemoveOrphan(t *testing.T) {
	proj := setupWorktreeProject(t)
	runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	feat := eval(t, filepath.Join(proj, "feat"))
	writeCache(feat, "test.json", map[string]string{"k": "v"})
	makeOrphan(t, proj, "feat")

	// Without --force: refused with an explanatory reason, dir intact.
	code, out := runWorktree(t, "remove", "feat", "--path", proj)
	if code != ExitOK {
		t.Fatalf("orphan refusal should be ExitOK, got %d: %s", code, out)
	}
	r := removeOut(t, out)
	if r.Removed || !hasWarning(r.Reasons, "orphan") || !hasWarning(r.Reasons, "--force") {
		t.Errorf("expected orphan refusal mentioning --force: %+v", r)
	}
	if _, err := os.Stat(filepath.Join(proj, "feat")); err != nil {
		t.Error("refusal must not touch the directory")
	}

	// With --force: dir and cache gone.
	code, out = runWorktree(t, "remove", "feat", "--force", "--path", proj)
	if code != ExitOK {
		t.Fatalf("orphan --force exit %d: %s", code, out)
	}
	r = removeOut(t, out)
	if !r.Removed {
		t.Fatalf("orphan --force should remove: %+v", r)
	}
	if _, err := os.Stat(filepath.Join(proj, "feat")); err == nil {
		t.Error("orphan dir should be gone")
	}
	if p, _ := cachePath(feat, ""); p != "" {
		if _, err := os.Stat(p); err == nil {
			t.Error("orphan cache tree should be deleted")
		}
	}

	// Again: now genuinely unknown — no invented work.
	r = removeOut(t, runArgs(t, "remove", "feat", "--force", "--path", proj))
	if r.Removed || !hasWarning(r.Reasons, "no worktree named") {
		t.Errorf("removed orphan should be plain not-found: %+v", r)
	}
}

func TestWorktreeRemoveOrphanGuards(t *testing.T) {
	proj := setupWorktreeProject(t)

	// The bare dir is never an orphan (dotted name fails ref validation too).
	r := removeOut(t, runArgs(t, "remove", ".bare", "--force", "--path", proj))
	if r.Removed {
		t.Error("must never remove .bare")
	}
	if _, err := os.Stat(filepath.Join(proj, ".bare")); err != nil {
		t.Error(".bare must be intact")
	}

	// An ancestor dir of a live nested worktree is not an orphan.
	runWorktree(t, "add", "feat/foo", "--no-get", "--path", proj)
	r = removeOut(t, runArgs(t, "remove", "feat", "--force", "--path", proj))
	if r.Removed {
		t.Error("ancestor of a live worktree must not be removed")
	}
	if _, err := os.Stat(filepath.Join(proj, "feat", "foo")); err != nil {
		t.Error("nested worktree must be intact")
	}

	// A plain file is not an orphan.
	file := filepath.Join(proj, "strayf")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	r = removeOut(t, runArgs(t, "remove", "strayf", "--force", "--path", proj))
	if r.Removed || !hasWarning(r.Reasons, "no worktree named") {
		t.Errorf("file should be plain not-found: %+v", r)
	}
	if _, err := os.Stat(file); err != nil {
		t.Error("file must be intact")
	}

	// A symlink is not an orphan (and its target must survive).
	link := filepath.Join(proj, "link")
	if err := os.Symlink(filepath.Join(proj, "main"), link); err != nil {
		t.Fatal(err)
	}
	r = removeOut(t, runArgs(t, "remove", "link", "--force", "--path", proj))
	if r.Removed {
		t.Error("symlink must not be removed")
	}
	if _, err := os.Lstat(link); err != nil {
		t.Error("symlink must be intact")
	}
	if _, err := os.Stat(filepath.Join(proj, "main")); err != nil {
		t.Error("symlink target must be intact")
	}
}

// --- orphans in list ---

func TestWorktreeListOrphans(t *testing.T) {
	proj := setupWorktreeProject(t)

	// Fresh project: field present, empty.
	_, lout := runWorktree(t, "list", "--path", proj)
	if !strings.Contains(lout, `"orphans"`) {
		t.Error("orphans field must always be emitted")
	}
	var list WorktreeListOutput
	mustJSON(t, lout, &list)
	if len(list.Orphans) != 0 {
		t.Errorf("fresh project should have no orphans: %+v", list.Orphans)
	}

	// One orphan among hidden-dir and plain-file distractors.
	runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	makeOrphan(t, proj, "feat")
	if err := os.MkdirAll(filepath.Join(proj, ".junk"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(proj, "note"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, lout = runWorktree(t, "list", "--path", proj)
	mustJSON(t, lout, &list)
	if len(list.Orphans) != 1 || list.Orphans[0].Name != "feat" {
		t.Fatalf("expected exactly the feat orphan: %+v", list.Orphans)
	}
	if !strings.Contains(list.Orphans[0].Hint, "worktree remove feat --force") {
		t.Errorf("hint should carry the reap command: %q", list.Orphans[0].Hint)
	}
	for _, w := range list.Worktrees {
		if w.Name == "feat" {
			t.Error("orphan must not appear as a worktree row")
		}
	}
}

// --- end-to-end failure arc ---

// A removal whose fallback also fails must exit non-zero and leave the state
// recoverable: the retry sees an orphan (not "no worktree named") and --force
// finishes the job.
func TestWorktreeRemoveFailsThenOrphanRecovery(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores file modes")
	}
	proj := setupWorktreeProject(t)
	runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	feat := eval(t, filepath.Join(proj, "feat"))
	writeCache(feat, "test.json", map[string]string{"k": "v"})

	locked := filepath.Join(proj, "feat", "locked")
	if err := os.MkdirAll(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(locked, "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(locked, 0o755) })

	code, out := runWorktree(t, "remove", "feat", "--force", "--path", proj)
	if code != ExitFailure {
		t.Fatalf("undeletable worktree should be ExitFailure, got %d: %s", code, out)
	}
	r := removeOut(t, out)
	if r.Removed || !hasWarning(r.Reasons, "fallback removal failed") {
		t.Errorf("expected combined failure reason: %+v", r)
	}
	if _, err := os.Stat(filepath.Join(proj, "feat")); err != nil {
		t.Fatal("directory must survive the failed removal")
	}

	// Unlock and retry — final state only: gone, cache included.
	if err := os.Chmod(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	code, out = runWorktree(t, "remove", "feat", "--force", "--path", proj)
	if code != ExitOK {
		t.Fatalf("recovery exit %d: %s", code, out)
	}
	if r := removeOut(t, out); !r.Removed {
		t.Fatalf("recovery should remove: %+v", r)
	}
	if _, err := os.Stat(filepath.Join(proj, "feat")); err == nil {
		t.Error("feat dir should be gone after recovery")
	}
	if p, _ := cachePath(feat, ""); p != "" {
		if _, err := os.Stat(p); err == nil {
			t.Error("feat cache tree should be gone after recovery")
		}
	}
}

// --- cache GC in prune ---

func TestWorktreePruneCacheGC(t *testing.T) {
	proj := setupWorktreeProject(t)
	evalProj := eval(t, proj)
	// A real package dir on disk so the sweep doesn't reap at the packages level.
	if err := os.MkdirAll(filepath.Join(proj, "main", "packages", "keep"), 0o755); err != nil {
		t.Fatal(err)
	}
	ghost := filepath.Join(evalProj, "ghost")
	gone := filepath.Join(evalProj, "main", "packages", "gone")
	keep := filepath.Join(evalProj, "main", "packages", "keep")
	for _, dir := range []string{ghost, gone, keep} {
		writeCache(dir, "test.json", map[string]string{"k": "v"})
	}
	writeCache(filepath.Join(evalProj, "main"), "git.json", map[string]string{"k": "v"})

	// Dry-run reports both orphans, deletes nothing.
	var pr WorktreePruneOutput
	_, out := runWorktree(t, "prune", "--dry-run", "--path", proj)
	mustJSON(t, out, &pr)
	if !containsString(pr.CacheRemoved, ghost) || !containsString(pr.CacheRemoved, gone) {
		t.Errorf("dry-run cache_removed missing orphans: %+v", pr.CacheRemoved)
	}
	for _, dir := range []string{ghost, gone} {
		if raw, _ := readCache(dir, "test.json"); raw == nil {
			t.Errorf("dry-run must not delete %s cache", dir)
		}
	}

	// Real prune reaps orphans, keeps live caches.
	_, out = runWorktree(t, "prune", "--path", proj)
	mustJSON(t, out, &pr)
	if !containsString(pr.CacheRemoved, ghost) || !containsString(pr.CacheRemoved, gone) {
		t.Errorf("cache_removed missing orphans: %+v", pr.CacheRemoved)
	}
	for _, dir := range []string{ghost, gone} {
		if raw, _ := readCache(dir, "test.json"); raw != nil {
			t.Errorf("orphaned cache %s should be reaped", dir)
		}
	}
	if raw, _ := readCache(keep, "test.json"); raw == nil {
		t.Error("live package cache must survive")
	}
	if raw, _ := readCache(filepath.Join(evalProj, "main"), "git.json"); raw == nil {
		t.Error("live worktree git.json must survive")
	}
}

func containsString(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}
