package cmd

import (
	"strings"
	"testing"
)

// Only an exact-basename pubspec.lock is generated churn — near-misses are
// hand-written files and must stay user_changes.
func TestSplitLockfiles(t *testing.T) {
	locks, others := splitLockfiles([]string{
		"pubspec.lock",
		"packages/a/pubspec.lock",
		"lib/x.dart",
		"pubspec.yaml",
		"pubspec.lock.bak",
	})
	wantLocks := []string{"pubspec.lock", "packages/a/pubspec.lock"}
	wantOthers := []string{"lib/x.dart", "pubspec.yaml", "pubspec.lock.bak"}
	if strings.Join(locks, ",") != strings.Join(wantLocks, ",") {
		t.Errorf("locks = %v, want %v", locks, wantLocks)
	}
	if strings.Join(others, ",") != strings.Join(wantOthers, ",") {
		t.Errorf("others = %v, want %v", others, wantOthers)
	}
}

// Parent-file dirt splits into user_changes (hand-written work) and
// stale_lockfiles (generated churn), user_changes first when both.
func TestClassifyDirt_ParentFiles(t *testing.T) {
	req := preflightRequest{Path: t.TempDir(), Repo: ".", Label: "worktree", ReRun: "re-run"}
	tests := []struct {
		name    string
		entries []porcelainEntry
		want    []BlockerCode
	}{
		{"lockfiles only", []porcelainEntry{
			{X: ' ', Y: 'M', Path: "pubspec.lock"},
			{X: ' ', Y: 'M', Path: "packages/a/pubspec.lock"},
		}, []BlockerCode{BlockerStaleLockfiles}},
		{"mixed puts user changes first", []porcelainEntry{
			{X: ' ', Y: 'M', Path: "pubspec.lock"},
			{X: ' ', Y: 'M', Path: "lib/x.dart"},
		}, []BlockerCode{BlockerUserChanges, BlockerStaleLockfiles}},
		{"staged-only file", []porcelainEntry{
			{X: 'M', Y: ' ', Path: "lib/y.dart"},
		}, []BlockerCode{BlockerUserChanges}},
		{"untracked file", []porcelainEntry{
			{X: '?', Y: '?', Path: "new.txt"},
		}, []BlockerCode{BlockerUserChanges}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			blockers := classifyDirt(req, tc.entries, nil, nil)
			if len(blockers) != len(tc.want) {
				t.Fatalf("got %d blockers %+v, want codes %v", len(blockers), blockers, tc.want)
			}
			for i, code := range tc.want {
				if blockers[i].Code != code {
					t.Errorf("blocker[%d].Code = %s, want %s", i, blockers[i].Code, code)
				}
			}
			if b := blockerFor(blockers, BlockerStaleLockfiles); b != nil && !strings.Contains(b.Hint, "glittering get") {
				t.Errorf("stale_lockfiles hint should name glittering get, got %q", b.Hint)
			}
		})
	}
}

// A dirty gitlink is judged on the heal's verdict for that path; the sync's
// own hint/error carry the remedy verbatim.
func TestClassifyDirt_SubmoduleFromSyncResult(t *testing.T) {
	req := preflightRequest{Path: t.TempDir(), Repo: ".", Label: "worktree", ReRun: "re-run"}
	entries := []porcelainEntry{{X: ' ', Y: 'M', Path: "sub"}}
	tests := []struct {
		name     string
		sync     GitSyncSubmodule
		want     BlockerCode
		wantText string // must appear in Message or Hint
	}{
		{"ahead", GitSyncSubmodule{Path: "sub", Action: "ahead",
			Hint: "glittering git commit --parent-only --path /w sub"},
			BlockerSubmoduleAhead, "--parent-only"},
		{"diverged", GitSyncSubmodule{Path: "sub", Action: "diverged",
			Error: "diverged from pinned ref abc (1 ahead / 2 behind)"},
			BlockerSubmoduleDiverged, "diverged from pinned ref"},
		{"error", GitSyncSubmodule{Path: "sub", Action: "error",
			Error: "submodule not initialised", Hint: "git submodule update --init"},
			BlockerSubmoduleUnsynced, "not initialised"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			blockers := classifyDirt(req, entries, []string{"sub"}, []GitSyncSubmodule{tc.sync})
			b := blockerFor(blockers, tc.want)
			if b == nil {
				t.Fatalf("expected a %s blocker, got %+v", tc.want, blockers)
			}
			if !strings.Contains(b.Message, tc.wantText) && !strings.Contains(b.Hint, tc.wantText) {
				t.Errorf("expected %q in message or hint, got %+v", tc.wantText, b)
			}
			if b.Hint != tc.sync.Hint {
				t.Errorf("hint should pass through the sync's remedy: got %q, want %q", b.Hint, tc.sync.Hint)
			}
		})
	}
}

// A staged gitlink (index differs from HEAD, worktree column clean) is the
// user's pending pin change, not a convergence problem.
func TestClassifyDirt_StagedGitlink(t *testing.T) {
	req := preflightRequest{Path: t.TempDir(), Repo: ".", Label: "worktree", ReRun: "re-run"}
	entries := []porcelainEntry{{X: 'M', Y: ' ', Path: "sub"}}
	blockers := classifyDirt(req, entries, []string{"sub"}, nil)
	b := blockerFor(blockers, BlockerUserChanges)
	if b == nil || !strings.Contains(b.Message, "staged") {
		t.Fatalf("expected a user_changes blocker naming the staged pin, got %+v", blockers)
	}
}

// Unclassifiable dirt is never a pass: a dirty gitlink whose submodule status
// cannot be read must still refuse.
func TestClassifyDirt_FailsClosed(t *testing.T) {
	req := preflightRequest{Path: t.TempDir(), Repo: ".", Label: "worktree", ReRun: "re-run"}
	entries := []porcelainEntry{{X: ' ', Y: 'M', Path: "sub"}} // no such dir under req.Path
	blockers := classifyDirt(req, entries, []string{"sub"}, nil)
	if len(blockers) == 0 {
		t.Fatal("unclassifiable dirt produced no blocker — a silent pass")
	}
	if !hasBlocker(blockers, BlockerStatusUnreadable) {
		t.Errorf("expected status_unreadable, got %+v", blockers)
	}
}

// The pass that moved the worktree wins; when both passes moved it the row
// spans them — the post sync's in_sync must not erase the pre-flight heal.
func TestMergeSyncResults(t *testing.T) {
	synced := func(from, to string, n int) GitSyncSubmodule {
		return GitSyncSubmodule{Path: "sub", Action: "synced", FromRef: from, ToRef: to, NewCommits: n}
	}
	inSync := GitSyncSubmodule{Path: "sub", Action: "in_sync", FromRef: "b"}

	tests := []struct {
		name      string
		pre, post []GitSyncSubmodule
		want      GitSyncSubmodule
	}{
		{"pre heal survives post in_sync", []GitSyncSubmodule{synced("a", "b", 2)}, []GitSyncSubmodule{inSync}, synced("a", "b", 2)},
		{"post move alone wins", []GitSyncSubmodule{inSync}, []GitSyncSubmodule{synced("b", "c", 1)}, synced("b", "c", 1)},
		{"both moved spans them", []GitSyncSubmodule{synced("a", "b", 2)}, []GitSyncSubmodule{synced("b", "c", 1)}, synced("a", "c", 3)},
		{"path only in pre survives", []GitSyncSubmodule{synced("a", "b", 2)}, nil, synced("a", "b", 2)},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := mergeSyncResults(tc.pre, tc.post)
			if len(got) != 1 || got[0] != tc.want {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
		})
	}
}

// The first hint is the more urgent; appendHint never drops one already set.
func TestFirstHintAndAppendHint(t *testing.T) {
	blockers := []Blocker{{Code: BlockerUserChanges}, {Code: BlockerStaleLockfiles, Hint: "run get"}}
	if got := firstHint(blockers); got != "run get" {
		t.Errorf("firstHint = %q, want the first non-empty", got)
	}
	if got := firstHint(nil); got != "" {
		t.Errorf("firstHint(nil) = %q, want empty", got)
	}
	if got := appendHint("", "b"); got != "b" {
		t.Errorf("appendHint over empty = %q", got)
	}
	if got := appendHint("a", "b"); !strings.Contains(got, "a") || !strings.Contains(got, "b") {
		t.Errorf("appendHint must keep both, got %q", got)
	}
}

// Only exact-basename pubspec.yaml paths count as dependency changes.
func TestFilterPubspecs(t *testing.T) {
	got := filterPubspecs([]string{
		"pubspec.yaml",
		"packages/a/pubspec.yaml",
		"packages/a/pubspec.lock",
		"lib/pubspec.yaml.tmpl",
		"other.txt",
	})
	want := []string{"pubspec.yaml", "packages/a/pubspec.yaml"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("filterPubspecs = %v, want %v", got, want)
	}
}
