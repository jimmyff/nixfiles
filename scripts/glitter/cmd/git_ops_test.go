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
