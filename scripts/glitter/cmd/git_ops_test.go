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

func TestGitCommitSub_MutualExclusivity_AllAndStaged(t *testing.T) {
	got := GitCommitSub([]string{"-m", "test", "--all", "--staged", "sub"})
	if got != ExitUsage {
		t.Errorf("--all + --staged: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitSub_MutualExclusivity_AllAndFiles(t *testing.T) {
	got := GitCommitSub([]string{"-m", "test", "--all", "--files", "a.dart", "sub"})
	if got != ExitUsage {
		t.Errorf("--all + --files: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitSub_MutualExclusivity_FilesAndStaged(t *testing.T) {
	got := GitCommitSub([]string{"-m", "test", "--files", "a.dart", "--staged", "sub"})
	if got != ExitUsage {
		t.Errorf("--files + --staged: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitSub_MutualExclusivity_AllThree(t *testing.T) {
	got := GitCommitSub([]string{"-m", "test", "--all", "--files", "a.dart", "--staged", "sub"})
	if got != ExitUsage {
		t.Errorf("all three flags: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitSub_MissingSubmoduleDir(t *testing.T) {
	tmp := t.TempDir()
	got := GitCommitSub([]string{"-m", "test", "--path", tmp, "nonexistent/sub"})
	if got != ExitUsage {
		t.Errorf("missing submodule dir: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitSub_MissingMessage(t *testing.T) {
	got := GitCommitSub([]string{"sub"})
	if got != ExitUsage {
		t.Errorf("missing message: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitParent_MissingSubmoduleDir(t *testing.T) {
	tmp := t.TempDir()
	got := GitCommitParent([]string{"-m", "test", "--path", tmp, "nonexistent/sub"})
	if got != ExitUsage {
		t.Errorf("missing submodule dir: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitParent_MissingMessage(t *testing.T) {
	got := GitCommitParent([]string{"sub"})
	if got != ExitUsage {
		t.Errorf("missing message: expected ExitUsage (%d), got %d", ExitUsage, got)
	}
}

func TestGitCommitSub_CommaFiles_MissingSubmoduleDir(t *testing.T) {
	tmp := t.TempDir()
	// Comma-separated files should be accepted (error will be about missing submodule, not about files)
	got := GitCommitSub([]string{"-m", "test", "--path", tmp, "-f", "a.dart,b.dart", "nonexistent/sub"})
	if got != ExitUsage {
		t.Errorf("comma files: expected ExitUsage (%d), got %d", ExitUsage, got)
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

// --- classifyParentFiles tests ---

func TestClassifyParentFiles_Empty(t *testing.T) {
	result := classifyParentFiles("", nil)
	if len(result.Staged) != 0 || len(result.Unstaged) != 0 {
		t.Errorf("empty: expected no files, got staged=%v unstaged=%v", result.Staged, result.Unstaged)
	}
}

func TestClassifyParentFiles_UnstagedOnly(t *testing.T) {
	input := " M README.md\n M lib/foo.dart"
	result := classifyParentFiles(input, nil)
	if len(result.Unstaged) != 2 {
		t.Errorf("expected 2 unstaged, got %d: %v", len(result.Unstaged), result.Unstaged)
	}
	if len(result.Staged) != 0 {
		t.Errorf("expected 0 staged, got %d: %v", len(result.Staged), result.Staged)
	}
}

func TestClassifyParentFiles_StagedOnly(t *testing.T) {
	input := "M  .github/workflows/kiln-firing.yml\nA  new-file.txt"
	result := classifyParentFiles(input, nil)
	if len(result.Staged) != 2 {
		t.Errorf("expected 2 staged, got %d: %v", len(result.Staged), result.Staged)
	}
	if len(result.Unstaged) != 0 {
		t.Errorf("expected 0 unstaged, got %d: %v", len(result.Unstaged), result.Unstaged)
	}
}

func TestClassifyParentFiles_DotDirectoryFiles(t *testing.T) {
	input := "M  .github/workflows/kiln-firing.yml\n M kiln/README.md"
	result := classifyParentFiles(input, nil)
	if len(result.Staged) != 1 || result.Staged[0] != ".github/workflows/kiln-firing.yml" {
		t.Errorf("staged: expected [.github/workflows/kiln-firing.yml], got %v", result.Staged)
	}
	if len(result.Unstaged) != 1 || result.Unstaged[0] != "kiln/README.md" {
		t.Errorf("unstaged: expected [kiln/README.md], got %v", result.Unstaged)
	}
}

func TestClassifyParentFiles_MixedStates(t *testing.T) {
	input := "MM both.dart\nM  staged-only.dart\n M unstaged-only.dart\nA  added.txt\n?? untracked.log"
	result := classifyParentFiles(input, nil)
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
	input := " M kiln\n M editor\n M README.md"
	subs := []string{"kiln", "editor"}
	result := classifyParentFiles(input, subs)
	if len(result.Unstaged) != 1 || result.Unstaged[0] != "README.md" {
		t.Errorf("expected only README.md unstaged, got %v", result.Unstaged)
	}
	if len(result.Staged) != 0 {
		t.Errorf("expected 0 staged, got %v", result.Staged)
	}
}

func TestClassifyParentFiles_Renamed(t *testing.T) {
	input := "R  old.txt -> new.txt"
	result := classifyParentFiles(input, nil)
	if len(result.Staged) != 1 || result.Staged[0] != "new.txt" {
		t.Errorf("rename: expected staged=[new.txt], got %v", result.Staged)
	}
}

func TestClassifyParentFiles_DeletedStaged(t *testing.T) {
	input := "D  removed-file.txt"
	result := classifyParentFiles(input, nil)
	if len(result.Staged) != 1 || result.Staged[0] != "removed-file.txt" {
		t.Errorf("delete: expected staged=[removed-file.txt], got %v", result.Staged)
	}
}

func TestClassifyParentFiles_ShortLines(t *testing.T) {
	input := "ab\n M valid.txt\nx"
	result := classifyParentFiles(input, nil)
	if len(result.Unstaged) != 1 || result.Unstaged[0] != "valid.txt" {
		t.Errorf("short lines: expected unstaged=[valid.txt], got %v", result.Unstaged)
	}
}

func TestClassifyParentFiles_Untracked(t *testing.T) {
	input := "?? .github/\n?? new-dir/file.txt"
	result := classifyParentFiles(input, nil)
	if len(result.Unstaged) != 2 {
		t.Errorf("expected 2 unstaged, got %d: %v", len(result.Unstaged), result.Unstaged)
	}
	if len(result.Staged) != 0 {
		t.Errorf("expected 0 staged, got %v", result.Staged)
	}
}
