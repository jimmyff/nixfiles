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
	// Isolate the global on-add hook lookup. This also hides ~/.config/git/config,
	// so provide an explicit git identity via env (hermetic — no dependency on the
	// runner's git config).
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("GIT_AUTHOR_NAME", "glittering-test")
	t.Setenv("GIT_AUTHOR_EMAIL", "test@example.com")
	t.Setenv("GIT_COMMITTER_NAME", "glittering-test")
	t.Setenv("GIT_COMMITTER_EMAIL", "test@example.com")
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
	if add.OnAddHook != "" {
		t.Errorf("no hook present, on_add_hook should be empty, got %q", add.OnAddHook)
	}

	// Object sharing was dissociated → no alternates file.
	alt := filepath.Join(proj, ".bare", "worktrees", "feat", "modules", "sub", "objects", "info", "alternates")
	if _, err := os.Stat(alt); err == nil {
		t.Errorf("submodule should be dissociated, found alternates at %s", alt)
	}

	// Submodule should be reattached to its branch, not left on detached HEAD.
	if b := strings.TrimSpace(gitOut(t, filepath.Join(proj, "feat", "sub"), "branch", "--show-current")); b != "main" {
		t.Errorf("submodule should be reattached to 'main', got %q (detached?)", b)
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

// --- on-add hook ---

// The hook writes the three GLITTER_* env vars to a RELATIVE path; it landing in
// the new worktree is direct proof cwd was the new worktree. Untracked in main.
func TestWorktreeAddHookRunsWithEnv(t *testing.T) {
	proj := setupWorktreeProject(t)
	main := eval(t, filepath.Join(proj, "main"))
	writeOnAddHook(t, main, `#!/bin/sh
printf '%s\n%s\n%s\n' "$GLITTER_WORKTREE_PATH" "$GLITTER_BASE_WORKTREE" "$GLITTER_PROJECT_DIR" > ./hook-env
`, 0o755)

	code, out := runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	if code != ExitOK {
		t.Fatalf("add exit %d: %s", code, out)
	}
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "ok" {
		t.Fatalf("on_add_hook = %q, want ok; warnings=%v", add.OnAddHook, add.Warnings)
	}

	feat := eval(t, filepath.Join(proj, "feat"))
	data, err := os.ReadFile(filepath.Join(feat, "hook-env"))
	if err != nil {
		t.Fatalf("hook-env not written inside new worktree: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 env lines, got %d: %q", len(lines), string(data))
	}
	if lines[0] != feat {
		t.Errorf("GLITTER_WORKTREE_PATH = %q, want %q", lines[0], feat)
	}
	if lines[1] != main {
		t.Errorf("GLITTER_BASE_WORKTREE = %q, want %q", lines[1], main)
	}
	if lines[2] != eval(t, proj) {
		t.Errorf("GLITTER_PROJECT_DIR = %q, want %q", lines[2], eval(t, proj))
	}
}

func TestWorktreeAddHookFailureNonFatal(t *testing.T) {
	proj := setupWorktreeProject(t)
	writeOnAddHook(t, eval(t, filepath.Join(proj, "main")), `#!/bin/sh
exit 1
`, 0o755)

	code, out := runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "failed" {
		t.Errorf("on_add_hook = %q, want failed", add.OnAddHook)
	}
	if !add.Success {
		t.Error("hook failure must be non-fatal (Success stays true)")
	}
	if code != ExitOK {
		t.Errorf("exit = %d, want ExitOK (hook failure is non-fatal)", code)
	}
	if !hasWarning(add.Warnings, "hook") {
		t.Errorf("expected a warning mentioning the hook, got %v", add.Warnings)
	}
}

func TestWorktreeAddHookNotExecutable(t *testing.T) {
	proj := setupWorktreeProject(t)
	writeOnAddHook(t, eval(t, filepath.Join(proj, "main")), `#!/bin/sh
touch ./hook-ran
`, 0o644)

	_, out := runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "not_executable" {
		t.Errorf("on_add_hook = %q, want not_executable", add.OnAddHook)
	}
	if !hasWarning(add.Warnings, "hook") {
		t.Errorf("expected a warning mentioning the hook, got %v", add.Warnings)
	}
	if _, err := os.Stat(filepath.Join(eval(t, filepath.Join(proj, "feat")), "hook-ran")); err == nil {
		t.Error("non-executable hook must not run")
	}
}

func TestWorktreeAddHookSkipped(t *testing.T) {
	proj := setupWorktreeProject(t)
	writeOnAddHook(t, eval(t, filepath.Join(proj, "main")), `#!/bin/sh
touch ./hook-ran
`, 0o755)

	_, out := runWorktree(t, "add", "feat", "--no-get", "--no-hook", "--path", proj)
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "skipped" {
		t.Errorf("on_add_hook = %q, want skipped", add.OnAddHook)
	}
	if hasWarning(add.Warnings, "hook") {
		t.Errorf("--no-hook should not warn about the hook, got %v", add.Warnings)
	}
	if _, err := os.Stat(filepath.Join(eval(t, filepath.Join(proj, "feat")), "hook-ran")); err == nil {
		t.Error("--no-hook must not run the hook")
	}
}

// The global (user-level) hook runs for every project, even with no project hook.
func TestWorktreeAddGlobalHookRuns(t *testing.T) {
	proj := setupWorktreeProject(t)
	writeGlobalOnAddHook(t, `#!/bin/sh
touch ./global-ran
`, 0o755)

	code, out := runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	if code != ExitOK {
		t.Fatalf("add exit %d: %s", code, out)
	}
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "ok" {
		t.Errorf("on_add_hook = %q, want ok; warnings=%v", add.OnAddHook, add.Warnings)
	}
	if _, err := os.Stat(filepath.Join(eval(t, filepath.Join(proj, "feat")), "global-ran")); err != nil {
		t.Errorf("global hook did not run in the new worktree: %v", err)
	}
}

// Both layers run, global before project.
func TestWorktreeAddGlobalAndProjectHooksRunInOrder(t *testing.T) {
	proj := setupWorktreeProject(t)
	writeGlobalOnAddHook(t, "#!/bin/sh\necho global >> ./order\n", 0o755)
	writeOnAddHook(t, eval(t, filepath.Join(proj, "main")), "#!/bin/sh\necho project >> ./order\n", 0o755)

	code, out := runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	if code != ExitOK {
		t.Fatalf("add exit %d: %s", code, out)
	}
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "ok" {
		t.Fatalf("on_add_hook = %q, want ok; warnings=%v", add.OnAddHook, add.Warnings)
	}
	data, err := os.ReadFile(filepath.Join(eval(t, filepath.Join(proj, "feat")), "order"))
	if err != nil {
		t.Fatalf("order file missing: %v", err)
	}
	got := strings.Fields(strings.TrimSpace(string(data)))
	if len(got) != 2 || got[0] != "global" || got[1] != "project" {
		t.Errorf("hook order = %v, want [global project]", got)
	}
}

// A failing global hook aggregates to "failed" with a scope-labelled warning,
// stays non-fatal, and does not stop the project hook.
func TestWorktreeAddGlobalHookFailureAggregates(t *testing.T) {
	proj := setupWorktreeProject(t)
	writeGlobalOnAddHook(t, "#!/bin/sh\nexit 1\n", 0o755)
	writeOnAddHook(t, eval(t, filepath.Join(proj, "main")), "#!/bin/sh\ntouch ./project-ran\n", 0o755)

	code, out := runWorktree(t, "add", "feat", "--no-get", "--path", proj)
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "failed" {
		t.Errorf("on_add_hook = %q, want failed (global failed)", add.OnAddHook)
	}
	if !add.Success || code != ExitOK {
		t.Errorf("hook failure must be non-fatal: success=%v exit=%d", add.Success, code)
	}
	if !hasWarning(add.Warnings, "global on-add hook failed") {
		t.Errorf("expected a scope-labelled global warning, got %v", add.Warnings)
	}
	if _, err := os.Stat(filepath.Join(eval(t, filepath.Join(proj, "feat")), "project-ran")); err != nil {
		t.Errorf("project hook should still run after global fails: %v", err)
	}
}

// --no-hook skips both layers.
func TestWorktreeAddNoHookSkipsBothLayers(t *testing.T) {
	proj := setupWorktreeProject(t)
	writeGlobalOnAddHook(t, "#!/bin/sh\ntouch ./global-ran\n", 0o755)
	writeOnAddHook(t, eval(t, filepath.Join(proj, "main")), "#!/bin/sh\ntouch ./project-ran\n", 0o755)

	_, out := runWorktree(t, "add", "feat", "--no-get", "--no-hook", "--path", proj)
	var add WorktreeAddOutput
	mustJSON(t, out, &add)
	if add.OnAddHook != "skipped" {
		t.Errorf("on_add_hook = %q, want skipped", add.OnAddHook)
	}
	feat := eval(t, filepath.Join(proj, "feat"))
	for _, marker := range []string{"global-ran", "project-ran"} {
		if _, err := os.Stat(filepath.Join(feat, marker)); err == nil {
			t.Errorf("--no-hook must skip both layers, but %s exists", marker)
		}
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

// writeOnAddHook installs an untracked on-add hook in the base worktree at the
// path glittering reads, with the given script body and exact mode (Chmod after
// write so umask can't strip the execute bits under test).
func writeOnAddHook(t *testing.T, mainPath, script string, mode os.FileMode) {
	t.Helper()
	dir := filepath.Join(mainPath, ".glittering", "hooks", "worktree")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir hook dir: %v", err)
	}
	hook := filepath.Join(dir, "on-add")
	if err := os.WriteFile(hook, []byte(script), mode); err != nil {
		t.Fatalf("write hook: %v", err)
	}
	if err := os.Chmod(hook, mode); err != nil {
		t.Fatalf("chmod hook: %v", err)
	}
}

// writeGlobalOnAddHook installs an executable user-level on-add hook under the
// test's isolated XDG_CONFIG_HOME (set by setupWorktreeProject); it runs for
// every project.
func writeGlobalOnAddHook(t *testing.T, script string, mode os.FileMode) {
	t.Helper()
	cfg := os.Getenv("XDG_CONFIG_HOME")
	if cfg == "" {
		t.Fatal("XDG_CONFIG_HOME not set (setupWorktreeProject should set it)")
	}
	dir := filepath.Join(cfg, "glittering", "hooks", "worktree")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir global hook dir: %v", err)
	}
	hook := filepath.Join(dir, "on-add")
	if err := os.WriteFile(hook, []byte(script), mode); err != nil {
		t.Fatalf("write global hook: %v", err)
	}
	if err := os.Chmod(hook, mode); err != nil {
		t.Fatalf("chmod global hook: %v", err)
	}
}

func hasWarning(warnings []string, substr string) bool {
	for _, w := range warnings {
		if strings.Contains(w, substr) {
			return true
		}
	}
	return false
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
