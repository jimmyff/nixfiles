package cmd

import (
	"strings"
	"testing"
)

func TestAnalyzeGitIssues_CleanRepo(t *testing.T) {
	data := GitOutput{
		Path: "/workspace",
		Repo: GitRepoStatus{
			Path:         ".",
			Branch:       "main",
			Ref:          "abc123",
			Upstream:     "origin/main",
			HeadOnRemote: true,
		},
		Submodules: []GitSubmoduleStatus{
			{
				Path:         "pkg/foo",
				Branch:       "main",
				Ref:          "def456",
				ParentRef:    "def456",
				Upstream:     "origin/main",
				HeadOnRemote: true,
			},
		},
	}
	issues := analyzeGitIssues(data)
	if len(issues) != 0 {
		t.Errorf("expected 0 issues for clean repo, got %d: %+v", len(issues), issues)
	}
}

func TestAnalyzeGitIssues_DirtyParent(t *testing.T) {
	data := GitOutput{
		Path: "/workspace",
		Repo: GitRepoStatus{
			Path:         ".",
			Branch:       "main",
			Dirty:        true,
			Upstream:     "origin/main",
			HeadOnRemote: true,
		},
		Submodules: []GitSubmoduleStatus{},
	}
	issues := analyzeGitIssues(data)
	found := false
	for _, issue := range issues {
		if issue.Type == "dirty" && issue.Repo == "." {
			found = true
			if issue.Severity != "error" {
				t.Errorf("dirty parent should be error severity, got %s", issue.Severity)
			}
		}
	}
	if !found {
		t.Error("expected dirty issue for parent repo")
	}
}

func TestAnalyzeGitIssues_UnpushedSubmodule(t *testing.T) {
	data := GitOutput{
		Path: "/workspace",
		Repo: GitRepoStatus{
			Path:         ".",
			Branch:       "main",
			Upstream:     "origin/main",
			HeadOnRemote: true,
		},
		Submodules: []GitSubmoduleStatus{
			{
				Path:         "pkg/bar",
				Branch:       "main",
				Ref:          "abc123",
				ParentRef:    "abc123",
				AheadRemote:  3,
				HeadOnRemote: false,
				Upstream:     "origin/main",
			},
		},
	}
	issues := analyzeGitIssues(data)
	found := false
	for _, issue := range issues {
		if issue.Type == "unpushed" && issue.Repo == "pkg/bar" {
			found = true
			if issue.Severity != "error" {
				t.Errorf("unpushed should be error severity, got %s", issue.Severity)
			}
			if issue.Fix == "" {
				t.Error("unpushed issue should have a fix command")
			}
		}
	}
	if !found {
		t.Error("expected unpushed issue for pkg/bar")
	}
}

func TestAnalyzeGitIssues_SubmoduleAheadOfParent(t *testing.T) {
	data := GitOutput{
		Path: "/workspace",
		Repo: GitRepoStatus{
			Path:         ".",
			Branch:       "main",
			Upstream:     "origin/main",
			HeadOnRemote: true,
		},
		Submodules: []GitSubmoduleStatus{
			{
				Path:         "pkg/baz",
				Branch:       "main",
				Ref:          "new123",
				ParentRef:    "old456",
				AheadParent:  2,
				Upstream:     "origin/main",
				HeadOnRemote: true,
			},
		},
	}
	issues := analyzeGitIssues(data)
	found := false
	for _, issue := range issues {
		if issue.Type == "ahead_parent" && issue.Repo == "pkg/baz" {
			found = true
			if issue.Severity != "warn" {
				t.Errorf("ahead_parent should be warn severity, got %s", issue.Severity)
			}
		}
	}
	if !found {
		t.Error("expected ahead_parent issue for pkg/baz")
	}
}

func TestAnalyzeGitIssues_MultipleIssues(t *testing.T) {
	data := GitOutput{
		Path: "/workspace",
		Repo: GitRepoStatus{
			Path:         ".",
			Branch:       "main",
			Dirty:        true,
			AheadRemote:  1,
			HeadOnRemote: false,
			Upstream:     "origin/main",
			StashCount:   2,
		},
		Submodules: []GitSubmoduleStatus{
			{
				Path:     "pkg/a",
				Detached: true,
			},
			{
				Path:         "pkg/b",
				Branch:       "main",
				Ref:          "abc",
				ParentRef:    "def",
				AheadParent:  1,
				BehindParent: 1,
				Upstream:     "origin/main",
				HeadOnRemote: true,
			},
		},
	}
	issues := analyzeGitIssues(data)
	// Parent: dirty (error), unpushed (error), stash (warn)
	// pkg/a: detached (error)
	// pkg/b: ahead_parent (warn), behind_parent (warn)
	errors, warns, infos := 0, 0, 0
	for _, issue := range issues {
		switch issue.Severity {
		case "error":
			errors++
		case "warn":
			warns++
		case "info":
			infos++
		}
	}
	if errors != 3 {
		t.Errorf("expected 3 errors, got %d", errors)
	}
	if warns != 3 {
		t.Errorf("expected 3 warns, got %d", warns)
	}
	if infos != 0 {
		t.Errorf("expected 0 infos, got %d", infos)
	}
}

// Regression: a submodule behind the parent's pinned ref silently builds stale
// code (analyzer errors that read as merge bugs) — it must break clean and
// carry an actionable fix, not vanish as an info.
func TestAnalyzeGitIssues_SubmoduleBehindParent(t *testing.T) {
	data := GitOutput{
		Path: "/workspace",
		Repo: GitRepoStatus{
			Path:         ".",
			Branch:       "main",
			Upstream:     "origin/main",
			HeadOnRemote: true,
		},
		Submodules: []GitSubmoduleStatus{
			{
				Path:         "pkg/stale",
				Branch:       "main",
				Ref:          "old456",
				ParentRef:    "new123",
				BehindParent: 2,
				Upstream:     "origin/main",
				HeadOnRemote: true,
			},
		},
	}
	issues := analyzeGitIssues(data)
	found := false
	for _, issue := range issues {
		if issue.Type == "behind_parent" && issue.Repo == "pkg/stale" {
			found = true
			if issue.Severity != "warn" {
				t.Errorf("behind_parent should be warn severity (must break clean), got %s", issue.Severity)
			}
			if !strings.Contains(issue.Fix, "git sync") {
				t.Errorf("behind_parent fix should point at git sync, got %q", issue.Fix)
			}
		}
	}
	if !found {
		t.Error("expected behind_parent issue for pkg/stale")
	}
	out := buildCheckOutput("/workspace", nil, issues)
	if out.Clean {
		t.Error("a stale submodule worktree must not report clean")
	}
}

func TestBuildCheckOutput_NilIssues(t *testing.T) {
	out := buildCheckOutput("/workspace", nil, nil)
	if !out.Clean {
		t.Error("expected clean=true for nil issues")
	}
	if len(out.Issues) != 0 {
		t.Errorf("expected empty issues slice, got %d", len(out.Issues))
	}
	if out.Summary.Errors != 0 || out.Summary.Warns != 0 || out.Summary.Infos != 0 {
		t.Errorf("expected zero summary counts, got %+v", out.Summary)
	}
}

func TestBuildCheckOutput_WithErrors(t *testing.T) {
	issues := []CheckIssue{
		{Repo: ".", Severity: "error", Type: "dirty", Message: "dirty"},
		{Repo: ".", Severity: "error", Type: "unpushed", Message: "unpushed"},
		{Repo: "pkg/a", Severity: "warn", Type: "stash", Message: "stash"},
		{Repo: "pkg/b", Severity: "info", Type: "note", Message: "note"},
	}
	ts := "2026-01-01T00:00:00Z"
	out := buildCheckOutput("/workspace", &ts, issues)
	if out.Clean {
		t.Error("expected clean=false with errors")
	}
	if out.Summary.Errors != 2 {
		t.Errorf("expected 2 errors, got %d", out.Summary.Errors)
	}
	if out.Summary.Warns != 1 {
		t.Errorf("expected 1 warn, got %d", out.Summary.Warns)
	}
	if out.Summary.Infos != 1 {
		t.Errorf("expected 1 info, got %d", out.Summary.Infos)
	}
	if out.Timestamp == nil || *out.Timestamp != ts {
		t.Errorf("expected timestamp %s, got %v", ts, out.Timestamp)
	}
}

func TestBuildCheckOutput_WarnsOnly(t *testing.T) {
	issues := []CheckIssue{
		{Repo: ".", Severity: "warn", Type: "stash", Message: "stash"},
	}
	out := buildCheckOutput("/workspace", nil, issues)
	if out.Clean {
		t.Error("expected clean=false with warnings")
	}
}

func TestBuildCheckOutput_InfosOnly(t *testing.T) {
	issues := []CheckIssue{
		{Repo: "pkg/a", Severity: "info", Type: "note", Message: "note"},
	}
	out := buildCheckOutput("/workspace", nil, issues)
	if !out.Clean {
		t.Error("expected clean=true with only info issues")
	}
}
