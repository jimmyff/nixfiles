package cmd

import (
	"path/filepath"
	"testing"
)

// --- pure ---

func TestParseSubmoduleStatus(t *testing.T) {
	out := " abc123 packages/one (heads/main)\n+def456 packages/two (heads/main)\n-999999 packages/three\nU777777 packages/four\n"
	got := parseSubmoduleStatus(out)
	if len(got) != 4 {
		t.Fatalf("expected 4 entries, got %d: %+v", len(got), got)
	}
	for i, want := range []submoduleStatusEntry{
		{' ', "packages/one"}, {'+', "packages/two"}, {'-', "packages/three"}, {'U', "packages/four"},
	} {
		if got[i] != want {
			t.Errorf("entry %d = %+v, want %+v", i, got[i], want)
		}
	}
	if len(parseSubmoduleStatus("")) != 0 {
		t.Error("empty output should yield no entries")
	}
}

func TestComputeOverlaps(t *testing.T) {
	rows := []WorktreeInfo{
		{Name: "main"},
		{Name: "feat-a", SubmodulesAhead: []string{"packages/kiln", "packages/blink"}},
		{Name: "feat-b", SubmodulesAhead: []string{"packages/kiln"}},
	}
	got := computeOverlaps(rows)
	if len(got) != 1 {
		t.Fatalf("only the shared submodule overlaps, got %+v", got)
	}
	if got[0].Submodule != "packages/kiln" {
		t.Errorf("submodule = %q, want packages/kiln", got[0].Submodule)
	}
	if len(got[0].Worktrees) != 2 || got[0].Worktrees[0] != "feat-a" || got[0].Worktrees[1] != "feat-b" {
		t.Errorf("worktrees = %v, want [feat-a feat-b] in row order", got[0].Worktrees)
	}
	if len(computeOverlaps(nil)) != 0 {
		t.Error("no rows ⇒ no overlaps (and never nil)")
	}
}

// --- live ---

// Two worktrees carrying commits in the same submodule is the collision an
// orchestrator needs to see before it spawns the second agent.
func TestWorktreeList_OverlapReported(t *testing.T) {
	proj := setupFeatureProject(t, "feat", "feat2")
	for _, name := range []string{"feat", "feat2"} {
		commitFileIn(t, filepath.Join(proj, name, "sub"), name+".txt", "work\n", "sub work in "+name)
	}

	list := runList(t, "--path", proj)
	if len(list.Overlaps) != 1 || list.Overlaps[0].Submodule != "sub" {
		t.Fatalf("expected one overlap on 'sub', got %+v", list.Overlaps)
	}
	if len(list.Overlaps[0].Worktrees) != 2 {
		t.Errorf("expected both worktrees, got %v", list.Overlaps[0].Worktrees)
	}
	for _, name := range []string{"feat", "feat2"} {
		row := findWT(t, list, name)
		if len(row.SubmodulesAhead) != 1 || row.SubmodulesAhead[0] != "sub" {
			t.Errorf("%s submodules_ahead = %v, want [sub]", name, row.SubmodulesAhead)
		}
	}
	if row := findWT(t, list, "main"); len(row.SubmodulesAhead) != 0 {
		t.Errorf("base worktree has no submodule work: %v", row.SubmodulesAhead)
	}
}

// One worktree editing a submodule is normal work, not a collision. A submodule
// merely behind its pin must not read as ahead either.
func TestWorktreeList_NoOverlapSingleWorktree(t *testing.T) {
	proj := setupFeatureProject(t, "feat", "feat2")
	commitFileIn(t, filepath.Join(proj, "feat", "sub"), "only.txt", "work\n", "sub work")
	// feat2's submodule ends up *behind* its pin (the state a merge leaves
	// before `git sync`) — differing from the pin, but not ahead of it.
	feat2 := wtPath(proj, "feat2")
	commitFileIn(t, filepath.Join(feat2, "sub"), "pinned.txt", "pinned\n", "sub work")
	gitRun(t, feat2, "add", "sub")
	gitRun(t, feat2, "commit", "--quiet", "-m", "bump sub pin")
	gitRun(t, filepath.Join(feat2, "sub"), "reset", "--hard", "--quiet", "HEAD~1")

	list := runList(t, "--path", proj)
	if len(list.Overlaps) != 0 {
		t.Errorf("expected no overlaps, got %+v", list.Overlaps)
	}
	if row := findWT(t, list, "feat"); len(row.SubmodulesAhead) != 1 {
		t.Errorf("feat should still report its own submodule work, got %v", row.SubmodulesAhead)
	}
	if row := findWT(t, list, "feat2"); len(row.SubmodulesAhead) != 0 {
		t.Errorf("a submodule behind its pin is not ahead: %v", row.SubmodulesAhead)
	}
}
