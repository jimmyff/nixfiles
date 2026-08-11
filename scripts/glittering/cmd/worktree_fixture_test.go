package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Fixture helpers shared by the worktree update/land/overlap tests. They build
// on setupWorktreeProject (worktree_test.go): a bare-repo project with a `main`
// worktree, one submodule, and bare origin remotes for both.

// setupFeatureProject returns a project with the base worktree plus a feature
// worktree named `feat` (submodules initialised, no pub get).
func setupFeatureProject(t *testing.T, names ...string) string {
	t.Helper()
	proj := setupWorktreeProject(t)
	if len(names) == 0 {
		names = []string{"feat"}
	}
	for _, name := range names {
		if code, out := runWorktree(t, "add", name, "--no-get", "--path", proj); code != ExitOK {
			t.Fatalf("worktree add %s: exit %d: %s", name, code, out)
		}
	}
	return proj
}

func wtPath(proj, name string) string { return filepath.Join(proj, name) }

// commitFileIn writes a file and commits it, returning the new HEAD.
func commitFileIn(t *testing.T, dir, rel, body, message string) string {
	t.Helper()
	full := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(full), err)
	}
	if err := os.WriteFile(full, []byte(body), 0o644); err != nil {
		t.Fatalf("write %s: %v", full, err)
	}
	gitRun(t, dir, "add", "--", rel)
	gitRun(t, dir, "commit", "--quiet", "-m", message)
	return headOf(t, dir)
}

func writeFileIn(t *testing.T, dir, rel, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, rel), []byte(body), 0o644); err != nil {
		t.Fatalf("write %s: %v", rel, err)
	}
}

func headOf(t *testing.T, dir string) string {
	t.Helper()
	return strings.TrimSpace(gitOut(t, dir, "rev-parse", "HEAD"))
}

func refOf(t *testing.T, dir, ref string) string {
	t.Helper()
	return strings.TrimSpace(gitOut(t, dir, "rev-parse", ref))
}

func remoteURLOf(t *testing.T, dir string) string {
	t.Helper()
	return strings.TrimSpace(gitOut(t, dir, "remote", "get-url", "origin"))
}

// isClean reports whether a repo has no status entries.
func isClean(t *testing.T, dir string) bool {
	t.Helper()
	return strings.TrimSpace(gitOut(t, dir, "status", "--porcelain")) == ""
}

// scratchClone clones a remote into a fresh temp dir — the way to move a remote
// branch without touching any of the project's worktrees.
func scratchClone(t *testing.T, url string) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "scratch")
	gitRun(t, t.TempDir(), "clone", "--quiet", url, dir)
	return dir
}

// pushScratchSubCommit commits a file on the submodule's origin/main via a
// scratch clone, simulating another worktree (or machine) publishing submodule
// work. Returns the new submodule commit.
func pushScratchSubCommit(t *testing.T, proj, sub, rel, message string) string {
	t.Helper()
	clone := scratchClone(t, remoteURLOf(t, filepath.Join(proj, "main", sub)))
	sha := commitFileIn(t, clone, rel, message+"\n", message)
	gitRun(t, clone, "push", "--quiet", "origin", "main")
	return sha
}

// pushScratchParentCommit moves the parent's origin/main via a scratch clone,
// leaving every worktree in the project untouched. mutate runs in the clone
// before the commit (see bumpPinIn for a gitlink change).
func pushScratchParentCommit(t *testing.T, proj string, mutate func(scratch string), message string) string {
	t.Helper()
	clone := scratchClone(t, remoteURLOf(t, filepath.Join(proj, ".bare")))
	mutate(clone)
	gitRun(t, clone, "add", "-A")
	gitRun(t, clone, "commit", "--quiet", "-m", message)
	gitRun(t, clone, "push", "--quiet", "origin", "main")
	return headOf(t, clone)
}

// bumpPinIn stages a new submodule pin without checking the submodule out —
// plumbing, so a scratch clone needs no submodule init.
func bumpPinIn(t *testing.T, scratch, sub, sha string) {
	t.Helper()
	gitRun(t, scratch, "update-index", "--cacheinfo", "160000,"+sha+","+sub)
}

// mergeInProgress reports whether a worktree has a merge left in progress.
func mergeInProgress(t *testing.T, dir string) bool {
	t.Helper()
	_, err := runGit(dir, "rev-parse", "--verify", "--quiet", "MERGE_HEAD")
	return err == nil
}

// remoteHasCommit reports whether a bare remote contains a commit.
func remoteHasCommit(t *testing.T, remoteDir, sha string) bool {
	t.Helper()
	_, err := runGit(remoteDir, "cat-file", "-e", sha+"^{commit}")
	return err == nil
}

func runUpdate(t *testing.T, args ...string) (int, WorktreeUpdateOutput) {
	t.Helper()
	var code int
	stdout := captureStdout(t, func() { code = Worktree(append([]string{"update"}, args...)) })
	var out WorktreeUpdateOutput
	mustJSON(t, stdout, &out)
	return code, out
}

func runLand(t *testing.T, args ...string) (int, WorktreeLandOutput) {
	t.Helper()
	var code int
	stdout := captureStdout(t, func() { code = Worktree(append([]string{"land"}, args...)) })
	var out WorktreeLandOutput
	mustJSON(t, stdout, &out)
	return code, out
}

func runList(t *testing.T, args ...string) WorktreeListOutput {
	t.Helper()
	_, stdout := runWorktree(t, append([]string{"list"}, args...)...)
	var out WorktreeListOutput
	mustJSON(t, stdout, &out)
	return out
}

// hasReason reports whether any reason mentions substr.
func hasReason(reasons []string, substr string) bool {
	for _, r := range reasons {
		if strings.Contains(r, substr) {
			return true
		}
	}
	return false
}
