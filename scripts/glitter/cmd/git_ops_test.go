package cmd

import "testing"

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
