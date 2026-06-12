package cmd

import (
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// initRepo creates a git repo at dir with user config so commits work.
func initRepo(t *testing.T, dir string) {
	t.Helper()
	for _, args := range [][]string{
		{"init", "--quiet", "--initial-branch=main"},
		{"config", "user.email", "test@example.com"},
		{"config", "user.name", "test"},
		{"commit", "--quiet", "--allow-empty", "-m", "init"},
	} {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v in %s failed: %v: %s", args, dir, err, out)
		}
	}
}

// captureStdout redirects os.Stdout for the duration of fn and returns what was written.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stdout = w
	done := make(chan string)
	go func() {
		b, _ := io.ReadAll(r)
		done <- string(b)
	}()
	fn()
	w.Close()
	os.Stdout = old
	return <-done
}

// Removed commands must fail fast with a migration error, not fall through
// to git status.
func TestGit_CommitSubRemoved(t *testing.T) {
	got := Git([]string{"commit-sub", "-m", "test", "sub"})
	if got != ExitUsage {
		t.Errorf("commit-sub: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGit_CommitParentRemoved(t *testing.T) {
	got := Git([]string{"commit-parent", "-m", "test", "sub"})
	if got != ExitUsage {
		t.Errorf("commit-parent: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

// --- GitCommit (unified) validation tests ---

func TestGitCommit_MissingMessage(t *testing.T) {
	got := GitCommit([]string{"sub"})
	if got != ExitUsage {
		t.Errorf("missing message: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_AllAndStaged(t *testing.T) {
	got := GitCommit([]string{"-m", "test", "--all", "--staged", "sub"})
	if got != ExitUsage {
		t.Errorf("--all + --staged: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_AllAndFiles(t *testing.T) {
	got := GitCommit([]string{"-m", "test", "--all", "-f", "a.dart", "sub"})
	if got != ExitUsage {
		t.Errorf("--all + --files: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_FilesAndStaged(t *testing.T) {
	got := GitCommit([]string{"-m", "test", "-f", "a.dart", "--staged", "sub"})
	if got != ExitUsage {
		t.Errorf("--files + --staged: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_NoParentAndParentOnly(t *testing.T) {
	got := GitCommit([]string{"-m", "test", "--no-parent", "--parent-only", "sub"})
	if got != ExitUsage {
		t.Errorf("--no-parent + --parent-only: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_FilesWithMultipleSubs(t *testing.T) {
	tmp := t.TempDir()
	got := GitCommit([]string{"-m", "test", "--path", tmp, "-f", "a.dart", "sub1", "sub2"})
	if got != ExitUsage {
		t.Errorf("--files + multiple subs: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_NoSubsNotParentOnly(t *testing.T) {
	got := GitCommit([]string{"-m", "test"})
	if got != ExitUsage {
		t.Errorf("no subs + not --parent-only: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_ParentOnlyWithAll_MissingMessage(t *testing.T) {
	got := GitCommit([]string{"--parent-only", "--all"})
	if got != ExitUsage {
		t.Errorf("--parent-only + --all without -m: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_ParentOnlyWithFiles_MissingMessage(t *testing.T) {
	got := GitCommit([]string{"--parent-only", "-f", "a.dart"})
	if got != ExitUsage {
		t.Errorf("--parent-only + --files without -m: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_ParentOnlyWithStaged_MissingMessage(t *testing.T) {
	got := GitCommit([]string{"--parent-only", "--staged"})
	if got != ExitUsage {
		t.Errorf("--parent-only + --staged without -m: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_ParentOnlyWithAllAndSubs(t *testing.T) {
	got := GitCommit([]string{"--parent-only", "--all", "-m", "test", "sub1"})
	if got != ExitUsage {
		t.Errorf("--parent-only + --all + subs: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_ParentOnlyWithFilesAndSubs(t *testing.T) {
	got := GitCommit([]string{"--parent-only", "-f", "a.txt", "-m", "test", "sub1"})
	if got != ExitUsage {
		t.Errorf("--parent-only + --files + subs: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_ParentOnlyWithStagedAndSubs(t *testing.T) {
	got := GitCommit([]string{"--parent-only", "--staged", "-m", "test", "sub1"})
	if got != ExitUsage {
		t.Errorf("--parent-only + --staged + subs: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_MissingSubmoduleDir(t *testing.T) {
	tmp := t.TempDir()
	got := GitCommit([]string{"-m", "test", "--path", tmp, "nonexistent/sub"})
	if got != ExitUsage {
		t.Errorf("missing submodule dir: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

// Regression: passing no staging flag with nothing already staged used to
// surface as "commit failed: exit status 1: " (empty). Now produces a clear
// "nothing staged" error before invoking git commit.
func TestGitCommit_EmptyStageProducesClearError(t *testing.T) {
	tmp := t.TempDir()
	initRepo(t, tmp)
	subDir := filepath.Join(tmp, "sub")
	if err := os.MkdirAll(subDir, 0755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	initRepo(t, subDir)

	var got int
	stdout := captureStdout(t, func() {
		got = GitCommit([]string{"-m", "test", "--path", tmp, "sub"})
	})

	if got != ExitFailure {
		t.Fatalf("expected ExitFailure (%d), got %d", ExitFailure, got)
	}
	var output GitCommitOutput
	if err := json.Unmarshal([]byte(stdout), &output); err != nil {
		t.Fatalf("output is not valid JSON: %v\noutput: %s", err, stdout)
	}
	if !strings.Contains(output.Error, "nothing staged") {
		t.Errorf("expected error to contain 'nothing staged', got: %q", output.Error)
	}
}

// --- parsePorcelainZ tests ---

func TestParsePorcelainZ_Empty(t *testing.T) {
	if entries := parsePorcelainZ(""); len(entries) != 0 {
		t.Errorf("empty: expected no entries, got %v", entries)
	}
}

// Regression: runGit trims stdout, which ate the leading space of the first
// porcelain line — " M PROJECT_PLAN.md" became "M PROJECT_PLAN.md", read as
// staged with the path truncated to "ROJECT_PLAN.md". The parser must receive
// untrimmed -z output (via runGitRaw) and preserve the first entry's columns.
func TestParsePorcelainZ_LeadingSpaceFirstEntryPreserved(t *testing.T) {
	input := " M PROJECT_PLAN.md\x00?? notes.txt\x00"
	entries := parsePorcelainZ(input)
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d: %v", len(entries), entries)
	}
	first := entries[0]
	if first.X != ' ' || first.Y != 'M' || first.Path != "PROJECT_PLAN.md" {
		t.Errorf("first entry: expected {' ' 'M' PROJECT_PLAN.md}, got {%q %q %s}", first.X, first.Y, first.Path)
	}
}

func TestParsePorcelainZ_RenameSkipsOriginToken(t *testing.T) {
	// In -z format a rename is "XY <to>\x00<from>\x00" — the origin path must
	// not be parsed as a separate entry.
	input := "R  new.txt\x00old.txt\x00 M other.md\x00"
	entries := parsePorcelainZ(input)
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d: %v", len(entries), entries)
	}
	if entries[0].X != 'R' || entries[0].Path != "new.txt" {
		t.Errorf("rename: expected {R new.txt}, got {%q %s}", entries[0].X, entries[0].Path)
	}
	if entries[1].Path != "other.md" {
		t.Errorf("expected second entry other.md, got %s", entries[1].Path)
	}
}

func TestParsePorcelainZ_MalformedTokensSkipped(t *testing.T) {
	input := "ab\x00 M valid.txt\x00x\x00"
	entries := parsePorcelainZ(input)
	if len(entries) != 1 || entries[0].Path != "valid.txt" {
		t.Errorf("malformed tokens: expected [valid.txt], got %v", entries)
	}
}

// --- classifyParentFiles tests ---

func TestClassifyParentFiles_Empty(t *testing.T) {
	result := classifyParentFiles(nil, nil)
	if len(result.Staged) != 0 || len(result.Unstaged) != 0 {
		t.Errorf("empty: expected no files, got staged=%v unstaged=%v", result.Staged, result.Unstaged)
	}
}

func TestClassifyParentFiles_UnstagedOnly(t *testing.T) {
	input := " M README.md\x00 M lib/foo.dart\x00"
	result := classifyParentFiles(parsePorcelainZ(input), nil)
	if len(result.Unstaged) != 2 {
		t.Errorf("expected 2 unstaged, got %d: %v", len(result.Unstaged), result.Unstaged)
	}
	if len(result.Staged) != 0 {
		t.Errorf("expected 0 staged, got %d: %v", len(result.Staged), result.Staged)
	}
}

func TestClassifyParentFiles_StagedOnly(t *testing.T) {
	input := "M  .github/workflows/kiln-firing.yml\x00A  new-file.txt\x00"
	result := classifyParentFiles(parsePorcelainZ(input), nil)
	if len(result.Staged) != 2 {
		t.Errorf("expected 2 staged, got %d: %v", len(result.Staged), result.Staged)
	}
	if len(result.Unstaged) != 0 {
		t.Errorf("expected 0 unstaged, got %d: %v", len(result.Unstaged), result.Unstaged)
	}
}

func TestClassifyParentFiles_MixedStates(t *testing.T) {
	input := "MM both.dart\x00M  staged-only.dart\x00 M unstaged-only.dart\x00A  added.txt\x00?? untracked.log\x00"
	result := classifyParentFiles(parsePorcelainZ(input), nil)
	// MM=unstaged (working-tree change), " M"=unstaged, "??"=unstaged
	if len(result.Unstaged) != 3 {
		t.Errorf("expected 3 unstaged, got %d: %v", len(result.Unstaged), result.Unstaged)
	}
	// "M "=staged, "A "=staged
	if len(result.Staged) != 2 {
		t.Errorf("expected 2 staged, got %d: %v", len(result.Staged), result.Staged)
	}
}

func TestClassifyParentFiles_SubmodulesFiltered(t *testing.T) {
	input := " M kiln\x00 M editor\x00 M README.md\x00"
	subs := []string{"kiln", "editor"}
	result := classifyParentFiles(parsePorcelainZ(input), subs)
	if len(result.Unstaged) != 1 || result.Unstaged[0] != "README.md" {
		t.Errorf("expected only README.md unstaged, got %v", result.Unstaged)
	}
	if len(result.Staged) != 0 {
		t.Errorf("expected 0 staged, got %v", result.Staged)
	}
}

func TestClassifyParentFiles_Renamed(t *testing.T) {
	input := "R  new.txt\x00old.txt\x00"
	result := classifyParentFiles(parsePorcelainZ(input), nil)
	if len(result.Staged) != 1 || result.Staged[0] != "new.txt" {
		t.Errorf("rename: expected staged=[new.txt], got %v", result.Staged)
	}
}

func TestClassifyParentFiles_DeletedStaged(t *testing.T) {
	input := "D  removed-file.txt\x00"
	result := classifyParentFiles(parsePorcelainZ(input), nil)
	if len(result.Staged) != 1 || result.Staged[0] != "removed-file.txt" {
		t.Errorf("delete: expected staged=[removed-file.txt], got %v", result.Staged)
	}
}

func TestClassifyParentFiles_Untracked(t *testing.T) {
	input := "?? .github/\x00?? new-dir/file.txt\x00"
	result := classifyParentFiles(parsePorcelainZ(input), nil)
	if len(result.Unstaged) != 2 {
		t.Errorf("expected 2 unstaged, got %d: %v", len(result.Unstaged), result.Unstaged)
	}
	if len(result.Staged) != 0 {
		t.Errorf("expected 0 staged, got %v", result.Staged)
	}
}

// --- --parent-files validation tests ---

func TestGitCommit_ParentFilesWithNoParent(t *testing.T) {
	got := GitCommit([]string{"-m", "test", "--no-parent", "-F", "PLAN.md", "sub"})
	if got != ExitUsage {
		t.Errorf("--parent-files + --no-parent: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommit_ParentFilesWithParentOnlyStaging(t *testing.T) {
	got := GitCommit([]string{"-m", "test", "--parent-only", "--all", "-F", "PLAN.md"})
	if got != ExitUsage {
		t.Errorf("--parent-files + --parent-only staging: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

// --- end-to-end commit tests (parent + submodule with bare remotes) ---

// gitRun runs a git command in dir, failing the test on error.
func gitRun(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v in %s failed: %v: %s", args, dir, err, out)
	}
}

// gitOut runs a git command in dir and returns its combined output.
func gitOut(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v in %s failed: %v: %s", args, dir, err, out)
	}
	return string(out)
}

// setupWorkspaceWithRemote creates a parent repo containing the named
// submodules (default: one named "sub"), all wired to bare origin remotes so
// push/fetch verification works. The parent tracks PROJECT_PLAN.md.
func setupWorkspaceWithRemote(t *testing.T, subNames ...string) string {
	t.Helper()
	if len(subNames) == 0 {
		subNames = []string{"sub"}
	}
	tmp := t.TempDir()

	makeBare := func(name string) string {
		r := filepath.Join(tmp, "remotes", name+".git")
		if err := os.MkdirAll(r, 0755); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
		gitRun(t, r, "init", "--quiet", "--bare", "--initial-branch=main")
		return r
	}

	parentRemote := makeBare("parent")
	parent := filepath.Join(tmp, "parent")
	if err := os.MkdirAll(parent, 0755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	initRepo(t, parent)
	gitRun(t, parent, "remote", "add", "origin", parentRemote)
	if err := os.WriteFile(filepath.Join(parent, "PROJECT_PLAN.md"), []byte("plan\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	gitRun(t, parent, "add", "PROJECT_PLAN.md")

	for _, name := range subNames {
		subRemote := makeBare(name)
		subSrc := filepath.Join(tmp, name+"-src")
		if err := os.MkdirAll(subSrc, 0755); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
		initRepo(t, subSrc)
		gitRun(t, subSrc, "remote", "add", "origin", subRemote)
		gitRun(t, subSrc, "push", "--quiet", "-u", "origin", "main")
		gitRun(t, parent, "-c", "protocol.file.allow=always", "submodule", "add", "--quiet", subRemote, name)
	}

	gitRun(t, parent, "commit", "--quiet", "-m", "add submodules")
	gitRun(t, parent, "push", "--quiet", "-u", "origin", "main")
	return parent
}

// Regression for the full reported failure: `git commit sub --all` with a
// dirty tracked parent file must (a) not claim the file will be included,
// (b) name it in full, and (c) surface it as partial + left_uncommitted.
func TestGitCommit_ParentFileLeftBehind_ReportedAsPartial(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)

	if err := os.WriteFile(filepath.Join(parent, "sub", "feature.txt"), []byte("new\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := os.WriteFile(filepath.Join(parent, "PROJECT_PLAN.md"), []byte("plan v2\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}

	var got int
	stdout := captureStdout(t, func() {
		got = GitCommit([]string{"-m", "feature", "--path", parent, "--all", "sub"})
	})
	if got != ExitPartial {
		t.Fatalf("expected ExitPartial (%d), got %d: %s", ExitPartial, got, stdout)
	}

	var output GitCommitOutput
	if err := json.Unmarshal([]byte(stdout), &output); err != nil {
		t.Fatalf("output is not valid JSON: %v\noutput: %s", err, stdout)
	}
	if !output.Success {
		t.Errorf("expected success=true, got: %s", stdout)
	}
	if !output.Partial {
		t.Errorf("expected partial=true when a parent file is left behind: %s", stdout)
	}
	if output.Parent == nil {
		t.Fatalf("expected parent result: %s", stdout)
	}
	if len(output.Parent.LeftUncommitted) != 1 || output.Parent.LeftUncommitted[0] != "PROJECT_PLAN.md" {
		t.Errorf("left_uncommitted: expected [PROJECT_PLAN.md], got %v", output.Parent.LeftUncommitted)
	}
	warnings := strings.Join(output.Parent.Warnings, "; ")
	if !strings.Contains(warnings, "PROJECT_PLAN.md") {
		t.Errorf("warning must name PROJECT_PLAN.md in full, got: %s", warnings)
	}
	if strings.Contains(warnings, "will be included") {
		t.Errorf("unstaged parent file must not be reported as included, got: %s", warnings)
	}
	// The parent commit itself must contain only the ref bump
	committed := gitOut(t, parent, "show", "--name-only", "--format=", "HEAD")
	if strings.Contains(committed, "PROJECT_PLAN.md") {
		t.Errorf("PROJECT_PLAN.md must not be in the parent commit:\n%s", committed)
	}
}

func TestGitCommit_ParentFilesIncludedInParentCommit(t *testing.T) {
	parent := setupWorkspaceWithRemote(t)

	if err := os.WriteFile(filepath.Join(parent, "sub", "feature.txt"), []byte("new\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := os.WriteFile(filepath.Join(parent, "PROJECT_PLAN.md"), []byte("plan v2\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}

	var got int
	stdout := captureStdout(t, func() {
		got = GitCommit([]string{"-m", "feature", "--path", parent, "--all", "-F", "PROJECT_PLAN.md", "sub"})
	})
	if got != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %s", got, stdout)
	}

	var output GitCommitOutput
	if err := json.Unmarshal([]byte(stdout), &output); err != nil {
		t.Fatalf("output is not valid JSON: %v\noutput: %s", err, stdout)
	}
	if !output.Success || output.Partial {
		t.Errorf("expected success=true partial=false, got: %s", stdout)
	}
	if output.Parent == nil {
		t.Fatalf("expected parent result: %s", stdout)
	}
	if len(output.Parent.LeftUncommitted) != 0 {
		t.Errorf("expected no left_uncommitted, got %v", output.Parent.LeftUncommitted)
	}
	found := false
	for _, s := range output.Parent.Staged {
		if s == "PROJECT_PLAN.md" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected PROJECT_PLAN.md in parent staged list, got %v", output.Parent.Staged)
	}
	committed := gitOut(t, parent, "show", "--name-only", "--format=", "HEAD")
	if !strings.Contains(committed, "PROJECT_PLAN.md") {
		t.Errorf("PROJECT_PLAN.md must be in the parent commit:\n%s", committed)
	}
	if !strings.Contains(committed, "sub") {
		t.Errorf("submodule ref bump must be in the parent commit:\n%s", committed)
	}
}

// When a later submodule fails after earlier ones were committed+pushed, the
// output must carry a recovery hint — the pushed subs' refs are now stale in
// the parent and need a follow-up --parent-only bump.
func TestGitCommit_LaterSubFailure_EmitsRecoveryHint(t *testing.T) {
	parent := setupWorkspaceWithRemote(t, "suba", "subb")

	// Only suba has changes; subb will fail the empty-stage check
	if err := os.WriteFile(filepath.Join(parent, "suba", "feature.txt"), []byte("new\n"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}

	var got int
	stdout := captureStdout(t, func() {
		got = GitCommit([]string{"-m", "feature", "--path", parent, "--all", "suba", "subb"})
	})
	if got != ExitFailure {
		t.Fatalf("expected ExitFailure (%d), got %d: %s", ExitFailure, got, stdout)
	}

	var output GitCommitOutput
	if err := json.Unmarshal([]byte(stdout), &output); err != nil {
		t.Fatalf("output is not valid JSON: %v\noutput: %s", err, stdout)
	}
	if output.Hint == "" {
		t.Fatalf("expected a recovery hint, got none: %s", stdout)
	}
	if !strings.Contains(output.Hint, "suba") || !strings.Contains(output.Hint, "--parent-only") {
		t.Errorf("hint should name suba and --parent-only, got: %s", output.Hint)
	}
	if strings.Contains(output.Hint, "subb") {
		t.Errorf("hint must not list the failed sub subb, got: %s", output.Hint)
	}
}
