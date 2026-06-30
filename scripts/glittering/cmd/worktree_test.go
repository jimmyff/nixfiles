package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// setupWorktreeProject builds a bare-repo + worktree layout (project/.bare,
// project/main) from a pushed parent+submodule workspace, mirroring ~/projects/*.
// Sets XDG_CACHE_HOME to a temp dir (isolated cache) and enables file-protocol
// submodule clones via env so production code stays clean.
func setupWorktreeProject(t *testing.T, subNames ...string) string {
	t.Helper()
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("GIT_CONFIG_COUNT", "1")
	t.Setenv("GIT_CONFIG_KEY_0", "protocol.file.allow")
	t.Setenv("GIT_CONFIG_VALUE_0", "always")

	parent := setupWorkspaceWithRemote(t, subNames...)
	parentRemote := strings.TrimSpace(gitOut(t, parent, "remote", "get-url", "origin"))

	projDir := filepath.Join(t.TempDir(), "proj")
	if err := os.MkdirAll(projDir, 0o755); err != nil {
		t.Fatalf("mkdir proj: %v", err)
	}
	gitRun(t, projDir, "clone", "--quiet", "--bare", parentRemote, ".bare")
	if err := os.WriteFile(filepath.Join(projDir, ".git"), []byte("gitdir: ./.bare\n"), 0o644); err != nil {
		t.Fatalf("write .git: %v", err)
	}
	bare := filepath.Join(projDir, ".bare")
	// A real ~/projects/.bare tracks origin; a plain --bare clone doesn't, so
	// set the fetch refspec + fetch to create refs/remotes/origin/* (needed for
	// head_on_remote / removable / prune to behave as in production).
	gitRun(t, bare, "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*")
	gitRun(t, bare, "fetch", "--quiet", "origin")
	gitRun(t, bare, "worktree", "add", filepath.Join(projDir, "main"), "main")
	gitRun(t, filepath.Join(projDir, "main"), "submodule", "update", "--init")
	return projDir
}

func runWorktree(t *testing.T, args ...string) (int, string) {
	t.Helper()
	var code int
	out := captureStdout(t, func() { code = Worktree(args) })
	return code, out
}

// --- pure ---

func TestParseWorktreePorcelain(t *testing.T) {
	out := strings.Join([]string{
		"worktree /p/.bare", "bare", "",
		"worktree /p/main", "HEAD abc", "branch refs/heads/main", "",
		"worktree /p/feat/foo", "HEAD def", "branch refs/heads/feat/foo", "",
		"worktree /p/loose", "HEAD 999", "detached", "",
	}, "\n")
	got := parseWorktreePorcelain(out, "/p")
	if len(got) != 3 {
		t.Fatalf("expected 3 worktrees (bare skipped), got %d: %+v", len(got), got)
	}
	if got[0].Name != "main" || got[0].Branch != "main" {
		t.Errorf("main: %+v", got[0])
	}
	if got[1].Name != "feat/foo" || got[1].Branch != "feat/foo" {
		t.Errorf("slashed name: %+v", got[1])
	}
	if got[2].Name != "loose" || !got[2].Detached || got[2].Branch != "" {
		t.Errorf("detached: %+v", got[2])
	}
}

func TestValidateWorktreeName(t *testing.T) {
	for _, ok := range []string{"feat", "feat/foo", "wt-1"} {
		if err := validateWorktreeName(ok); err != nil {
			t.Errorf("expected %q valid: %v", ok, err)
		}
	}
	for _, bad := range []string{"", "../x", "/abs", "a..b", "-x"} {
		if err := validateWorktreeName(bad); err == nil {
			t.Errorf("expected %q invalid", bad)
		}
	}
}

func TestCacheTreeGuards(t *testing.T) {
	if _, err := copyCacheTree("", "/x"); err == nil {
		t.Error("copyCacheTree should refuse empty src")
	}
	if err := deleteCacheTree(""); err == nil {
		t.Error("deleteCacheTree should refuse empty root")
	}
	if err := deleteCacheTree("/"); err == nil {
		t.Error("deleteCacheTree should refuse filesystem root")
	}
}

func TestCopyCacheTreeSkipsGitJsonAndRelocates(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	src := filepath.Join(t.TempDir(), "src")
	dst := filepath.Join(t.TempDir(), "dst")
	// Both "package dirs" must exist in dst for the relocation to copy.
	if err := os.MkdirAll(dst, 0o755); err != nil {
		t.Fatal(err)
	}
	writeCache(src, "test.json", map[string]string{"k": "v"})
	writeCache(src, "git.json", map[string]string{"k": "v"})

	n, err := copyCacheTree(src, dst)
	if err != nil {
		t.Fatalf("copy: %v", err)
	}
	if n != 1 {
		t.Errorf("expected 1 file copied (git.json skipped), got %d", n)
	}
	if raw, _ := readCache(dst, "test.json"); raw == nil {
		t.Error("test.json should have been copied")
	}
	if raw, _ := readCache(dst, "git.json"); raw != nil {
		t.Error("git.json must NOT be copied (branch-specific)")
	}
}

// --- discovery ---

func TestWorktreeDiscover(t *testing.T) {
	proj := setupWorktreeProject(t)
	main := filepath.Join(proj, "main")
	bare := filepath.Join(proj, ".bare")

	for _, root := range []string{main, proj, bare} {
		info, metas, err := discoverWorktrees(root)
		if err != nil {
			t.Fatalf("discover from %s: %v", root, err)
		}
		if info.BaseBranch != "main" || info.ProjectName != filepath.Base(proj) {
			t.Errorf("from %s: %+v", root, info)
		}
		if len(metas) != 1 || metas[0].Name != "main" {
			t.Errorf("from %s: metas %+v", root, metas)
		}
	}
	// Current is only set when --path is inside a worktree (git returns
	// symlink-resolved paths; resolve the expected side to match on macOS /var).
	if info, _, _ := discoverWorktrees(main); info.CurrentPath != eval(t, main) {
		t.Errorf("CurrentPath from main = %q, want %q", info.CurrentPath, eval(t, main))
	}
	if info, _, _ := discoverWorktrees(proj); info.CurrentPath != "" {
		t.Errorf("CurrentPath from project root = %q, want empty", info.CurrentPath)
	}
}

// --- list + add ---

func TestWorktreeAddAndList(t *testing.T) {
	proj := setupWorktreeProject(t)
	// Seed main's cache (test.json) so add has something to copy; tool uses
	// git-resolved paths, so seed at the resolved main path.
	writeCache(eval(t, filepath.Join(proj, "main")), "test.json", map[string]string{"k": "v"})

	code, out := runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	if code != ExitOK {
		t.Fatalf("add exit %d: %s", code, out)
	}
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if !add.Success || !add.CreatedBranch || add.Branch != "feat" || add.Base != "main" {
		t.Errorf("add: %+v", add)
	}
	if add.SubmodulesExpected != 1 || add.SubmodulesInitialised != 1 {
		t.Errorf("submodules %d/%d", add.SubmodulesInitialised, add.SubmodulesExpected)
	}
	if len(add.PubGet) != 0 {
		t.Errorf("--no-get should skip pub get, got %d", len(add.PubGet))
	}
	if !add.CacheSeeded {
		t.Error("expected cache seeded from main (main has no cache yet?)")
	}

	// Object sharing was dissociated → no alternates file.
	alt := filepath.Join(proj, ".bare", "worktrees", "feat", "modules", "sub", "objects", "info", "alternates")
	if _, err := os.Stat(alt); err == nil {
		t.Errorf("submodule should be dissociated, found alternates at %s", alt)
	}

	// List shows both; feat is removable (fresh off main, nothing unique), not current.
	_, lout := runWorktree(t, "list", "--path", proj)
	var list WorktreeListOutput
	mustJSON(t, lout, &list)
	if len(list.Worktrees) != 2 {
		t.Fatalf("expected 2 worktrees, got %d", len(list.Worktrees))
	}
	feat := findWT(t, list, "feat")
	if !feat.Removable || feat.UninitSubmodules != 0 {
		t.Errorf("fresh feat should be removable, clean subs: %+v", feat)
	}

	// Dirtying feat makes it non-removable.
	if err := os.WriteFile(filepath.Join(proj, "feat", "dirty.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, lout2 := runWorktree(t, "list", "--path", proj)
	var list2 WorktreeListOutput
	mustJSON(t, lout2, &list2)
	if findWT(t, list2, "feat").Removable {
		t.Error("dirty feat must not be removable")
	}
}

func TestWorktreeAddExistingLocalBranch(t *testing.T) {
	proj := setupWorktreeProject(t)
	gitRun(t, filepath.Join(proj, "main"), "branch", "existing")
	_, out := runWorktree(t, "add", "existing", "--no-get", "--path", proj)
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.CreatedBranch {
		t.Errorf("existing branch should be checked out, not created: %+v", add)
	}
}

func TestWorktreeAddCollision(t *testing.T) {
	proj := setupWorktreeProject(t)
	if code, _ := runWorktree(t, "add", "main", "--no-get", "--path", proj); code != ExitUsage {
		t.Errorf("adding existing worktree name should be ExitUsage, got %d", code)
	}
	if code, _ := runWorktree(t, "add", "../escape", "--no-get", "--path", proj); code != ExitUsage {
		t.Errorf("traversing name should be ExitUsage, got %d", code)
	}
}

// --- remove ---

func TestWorktreeRemove(t *testing.T) {
	proj := setupWorktreeProject(t)
	runWorktree(t, "add", "feat", "--no-get", "--path", proj)

	// Refuse base + current.
	if r := removeOut(t, runArgs(t, "remove", "main", "--path", proj)); r.Removed {
		t.Error("must refuse removing base worktree")
	}
	if r := removeOut(t, runArgs(t, "remove", "main", "--path", filepath.Join(proj, "main"))); r.Removed {
		t.Error("must refuse removing current worktree")
	}

	// Refuse dirty without --force.
	if err := os.WriteFile(filepath.Join(proj, "feat", "d.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if r := removeOut(t, runArgs(t, "remove", "feat", "--path", proj)); r.Removed {
		t.Errorf("must refuse dirty feat: %+v", r.Reasons)
	}

	// --force removes it and deletes the cache tree.
	r := removeOut(t, runArgs(t, "remove", "feat", "--force", "--path", proj))
	if !r.Removed {
		t.Fatalf("force remove failed: %+v", r.Reasons)
	}
	if _, err := os.Stat(filepath.Join(proj, "feat")); err == nil {
		t.Error("feat worktree dir should be gone")
	}
	if p, _ := cachePath(filepath.Join(proj, "feat"), ""); p != "" {
		if _, err := os.Stat(p); err == nil {
			t.Error("feat cache tree should be deleted")
		}
	}
}

// A clean worktree with submodules must remove WITHOUT --force: submodules sit
// in detached HEAD at their pinned ref, which is normal, not a blocker.
func TestWorktreeRemoveCleanNoForce(t *testing.T) {
	proj := setupWorktreeProject(t)
	runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	r := removeOut(t, runArgs(t, "remove", "feat", "--path", proj))
	if !r.Removed {
		t.Fatalf("clean worktree should remove without --force (detached submodules are normal): %+v", r.Reasons)
	}
	if _, err := os.Stat(filepath.Join(proj, "feat")); err == nil {
		t.Error("feat dir should be gone")
	}
}

func TestWorktreeRemoveNotFound(t *testing.T) {
	proj := setupWorktreeProject(t)
	code, out := runWorktree(t, "remove", "ghost", "--path", proj)
	if code != ExitOK {
		t.Errorf("not-found should be ExitOK (query answered), got %d", code)
	}
	var r WorktreeRemoveOutput
	mustJSON(t, out, &r)
	if r.Removed || len(r.Reasons) == 0 {
		t.Errorf("expected removed:false + reason: %+v", r)
	}
}

// --- prune ---

func TestWorktreePrune(t *testing.T) {
	proj := setupWorktreeProject(t)
	runWorktree(t, "add", "fresh", "--no-get", "--path", proj) // ahead_base 0 → eligible

	// An unmerged-but-pushed worktree is skipped (not merged).
	runWorktree(t, "add", "work", "--no-get", "--path", proj)
	work := filepath.Join(proj, "work")
	if err := os.WriteFile(filepath.Join(work, "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitRun(t, work, "add", "f.txt")
	gitRun(t, work, "commit", "--quiet", "-m", "work")
	gitRun(t, work, "push", "--quiet", "-u", "origin", "work")

	// Dry-run: fresh is a candidate, work is skipped.
	var dry WorktreePruneOutput
	_, dout := runWorktree(t, "prune", "--dry-run", "--path", proj)
	mustJSON(t, dout, &dry)
	if !containsEntry(dry.Pruned, "fresh") {
		t.Errorf("fresh (merged) should be a prune candidate: %+v", dry)
	}
	if !containsEntry(dry.Skipped, "work") {
		t.Errorf("work (unmerged) should be skipped: %+v", dry)
	}
	if _, err := os.Stat(filepath.Join(proj, "fresh")); err != nil {
		t.Error("dry-run must not remove anything")
	}

	// Real prune removes fresh, keeps work.
	runWorktree(t, "prune", "--path", proj)
	if _, err := os.Stat(filepath.Join(proj, "fresh")); err == nil {
		t.Error("fresh should be pruned")
	}
	if _, err := os.Stat(filepath.Join(proj, "work")); err != nil {
		t.Error("work should survive prune")
	}
	// Branch survives even after its worktree is pruned.
	if out := gitOut(t, filepath.Join(proj, "main"), "branch", "--list", "fresh"); !strings.Contains(out, "fresh") {
		t.Error("prune must not delete the branch")
	}
}

// --- path ---

func TestWorktreePath(t *testing.T) {
	proj := setupWorktreeProject(t)
	code, out := runWorktree(t, "path", "main", "--path", proj)
	if code != ExitOK || strings.TrimSpace(out) != eval(t, filepath.Join(proj, "main")) {
		t.Errorf("path main = %q (exit %d)", out, code)
	}
	if code, _ := runWorktree(t, "path", "ghost", "--path", proj); code != ExitFailure {
		t.Errorf("unknown name should be ExitFailure, got %d", code)
	}
}

// --- helpers ---

func eval(t *testing.T, p string) string {
	t.Helper()
	r, err := filepath.EvalSymlinks(p)
	if err != nil {
		t.Fatalf("evalsymlinks %s: %v", p, err)
	}
	return r
}

func mustJSON(t *testing.T, out string, v interface{}) {
	t.Helper()
	if err := json.Unmarshal([]byte(out), v); err != nil {
		t.Fatalf("invalid JSON: %v\n%s", err, out)
	}
}

func findWT(t *testing.T, list WorktreeListOutput, name string) WorktreeInfo {
	t.Helper()
	for _, w := range list.Worktrees {
		if w.Name == name {
			return w
		}
	}
	t.Fatalf("worktree %q not in list", name)
	return WorktreeInfo{}
}

func runArgs(t *testing.T, args ...string) string {
	t.Helper()
	_, out := runWorktree(t, args...)
	return out
}

func removeOut(t *testing.T, out string) WorktreeRemoveOutput {
	t.Helper()
	var r WorktreeRemoveOutput
	mustJSON(t, out, &r)
	return r
}

func containsEntry(entries []WorktreePruneEntry, name string) bool {
	for _, e := range entries {
		if e.Name == name {
			return true
		}
	}
	return false
}
