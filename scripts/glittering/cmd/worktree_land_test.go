package cmd

import (
	"path/filepath"
	"strings"
	"testing"
)

// landableFeature gives `feat` a submodule commit, the matching pin bump and a
// parent commit — the state an agent finishes a task in.
func landableFeature(t *testing.T, proj string) (featHead, subHead string) {
	t.Helper()
	feat := wtPath(proj, "feat")
	subHead = commitFileIn(t, filepath.Join(feat, "sub"), "feature.txt", "sub work\n", "sub work")
	gitRun(t, feat, "add", "sub")
	gitRun(t, feat, "commit", "--quiet", "-m", "bump sub pin")
	featHead = commitFileIn(t, feat, "PROJECT_PLAN.md", "plan v2\n", "plan v2")
	return featHead, subHead
}

func TestWorktreeLand_HappyPath(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	parentRemote := remoteURLOf(t, filepath.Join(proj, ".bare"))
	subRemote := remoteURLOf(t, filepath.Join(main, "sub"))
	featHead, subHead := landableFeature(t, proj)

	var code int
	stdout := captureStdout(t, func() { code = Worktree([]string{"land", "--path", feat}) })
	var out WorktreeLandOutput
	mustJSON(t, stdout, &out)
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	// Empty lists, never null — agents index into these.
	for _, field := range []string{`"skipped": []`, `"failed": []`} {
		if !strings.Contains(stdout, field) {
			t.Errorf("expected %s in the output, got:\n%s", field, stdout)
		}
	}
	if !out.Success || !out.Landed {
		t.Fatalf("expected landed+success: %+v", out)
	}

	// Submodules are published before the parent commit that references them.
	if len(out.Pushed) != 2 || out.Pushed[0].Path != "sub" || out.Pushed[1].Path != "." {
		t.Fatalf("expected [sub, .] pushed in that order, got %+v", out.Pushed)
	}
	if !remoteHasCommit(t, subRemote, subHead) {
		t.Error("submodule commit should be on its remote")
	}
	if got := refOf(t, parentRemote, "refs/heads/feat"); got != featHead {
		t.Errorf("feature branch on origin = %s, want %s", got, featHead)
	}

	// main fast-forwarded onto the feature, locally and on the remote.
	if out.Base.Action != "fast_forwarded" || out.Base.NewCommits != 2 || !out.Base.Pushed {
		t.Errorf("base: expected fast_forwarded (2 commits) + pushed, got %+v", out.Base)
	}
	if got := headOf(t, main); got != featHead {
		t.Errorf("base worktree HEAD = %s, want %s", got, featHead)
	}
	if got := refOf(t, parentRemote, "refs/heads/main"); got != featHead {
		t.Errorf("origin/main = %s, want %s", got, featHead)
	}

	// The base worktree is left usable: pins converged, nothing dirty.
	if got := headOf(t, filepath.Join(main, "sub")); got != subHead {
		t.Errorf("base submodule HEAD = %s, want the landed pin %s", got, subHead)
	}
	if !isClean(t, main) {
		t.Errorf("base worktree left dirty:\n%s", gitOut(t, main, "status", "--porcelain"))
	}
	if !strings.Contains(out.Hint, "prune") {
		t.Errorf("hint should point at prune, got %q", out.Hint)
	}
	// Land never removes the worktree.
	if headOf(t, feat) != featHead {
		t.Error("feature worktree must survive land, unchanged")
	}
}

// A feature that doesn't contain origin/main is refused with `update` as the
// single remedy — and nothing is published.
func TestWorktreeLand_NotIntegratedRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	parentRemote := remoteURLOf(t, filepath.Join(proj, ".bare"))
	landableFeature(t, proj)
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "other.txt", "other\n")
	}, "concurrent main work")
	baseBefore, originBefore := headOf(t, main), refOf(t, parentRemote, "refs/heads/main")

	code, out := runLand(t, "--path", feat)
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
	}
	if !hasReason(out.Reasons, "does not contain") || !strings.Contains(out.Hint, "worktree update") {
		t.Errorf("expected a not-contained refusal pointing at update: %+v / %q", out.Reasons, out.Hint)
	}
	if len(out.Pushed) != 0 || out.Landed {
		t.Errorf("a refusal must publish nothing: %+v", out)
	}
	if _, err := runGit(parentRemote, "rev-parse", "--verify", "--quiet", "refs/heads/feat"); err == nil {
		t.Error("feature branch must not be pushed on a refusal")
	}
	if headOf(t, main) != baseBefore || refOf(t, parentRemote, "refs/heads/main") != originBefore {
		t.Error("main must be untouched on a refusal")
	}
}

func TestWorktreeLand_DirtyRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	landableFeature(t, proj)

	writeFileIn(t, feat, "wip.txt", "wip\n")
	code, out := runLand(t, "--path", feat)
	if code != ExitFailure || !hasReason(out.Reasons, "uncommitted changes") {
		t.Fatalf("dirty feature should be refused, got %d: %+v", code, out.Reasons)
	}
	if len(out.Pushed) != 0 {
		t.Errorf("nothing should be pushed: %+v", out.Pushed)
	}
	gitRun(t, feat, "clean", "-qf")

	writeFileIn(t, main, "local.txt", "local\n")
	code, out = runLand(t, "--path", feat)
	if code != ExitFailure || !hasReason(out.Reasons, "base worktree") {
		t.Fatalf("dirty base should be refused, got %d: %+v", code, out.Reasons)
	}
	if !hasReason(out.Reasons, "local.txt") {
		t.Errorf("the refusal should name the offending file: %+v", out.Reasons)
	}
}

// Two worktrees editing the same submodule: the second one's push would be
// rejected, so land refuses in pre-flight rather than publishing half of it.
func TestWorktreeLand_NonFFSubmodulePushRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	parentRemote := remoteURLOf(t, filepath.Join(proj, ".bare"))
	subRemote := remoteURLOf(t, filepath.Join(proj, "main", "sub"))
	landableFeature(t, proj)
	otherSha := pushScratchSubCommit(t, proj, "sub", "other.txt", "concurrent sub work")

	code, out := runLand(t, "--path", feat)
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
	}
	if !hasReason(out.Reasons, "diverged") || !hasReason(out.Reasons, "sub") {
		t.Errorf("expected a diverged-submodule refusal, got %+v", out.Reasons)
	}
	if !hasReason(out.Reasons, "--parent-only") {
		t.Errorf("the refusal should spell out the integrate-then-bump remedy: %+v", out.Reasons)
	}
	if len(out.Pushed) != 0 || out.Landed {
		t.Errorf("a refusal must publish nothing: %+v", out)
	}
	if got := refOf(t, subRemote, "refs/heads/main"); got != otherSha {
		t.Errorf("submodule remote moved on a refusal: %s", got)
	}
	if _, err := runGit(parentRemote, "rev-parse", "--verify", "--quiet", "refs/heads/feat"); err == nil {
		t.Error("feature branch must not be pushed on a refusal")
	}
}

// rewindPinViaConflict reproduces the pin-rewind trap end to end: main bumps a
// pin in a commit that also conflicts, and the conflict is resolved with
// `git add -A` — which re-stages the gitlink at the submodule worktree's HEAD,
// dropping the pin the merge had staged. Returns main's (now newer) pin.
func rewindPinViaConflict(t *testing.T, proj string) string {
	t.Helper()
	feat := wtPath(proj, "feat")
	commitFileIn(t, feat, "PROJECT_PLAN.md", "feature side\n", "feature edit")
	subSha := pushScratchSubCommit(t, proj, "sub", "b.txt", "sub work")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "PROJECT_PLAN.md", "main side\n")
		bumpPinIn(t, s, "sub", subSha)
	}, "main edit + pin bump")

	runUpdate(t, "--path", feat) // conflicts on PROJECT_PLAN.md
	writeFileIn(t, feat, "PROJECT_PLAN.md", "resolved\n")
	gitRun(t, feat, "add", "-A")
	gitRun(t, feat, "commit", "--quiet", "--no-edit")
	return subSha
}

// A fast-forwardable parent history says nothing about gitlinks: this feature
// contains main yet records an older pin, so landing it would revert published
// submodule work. Refuse, and publish nothing.
func TestWorktreeLand_PinRegressionRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	parentRemote := remoteURLOf(t, filepath.Join(proj, ".bare"))
	subSha := rewindPinViaConflict(t, proj)
	baseBefore := headOf(t, main)

	code, out := runLand(t, "--path", feat)
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
	}
	if !hasReason(out.Reasons, "is behind") || !hasReason(out.Reasons, "sub") {
		t.Errorf("expected a pin-rewind refusal naming the submodule, got %+v", out.Reasons)
	}
	if !hasReason(out.Reasons, "--allow-pin-rewind") {
		t.Errorf("the refusal should name the override for a deliberate revert: %+v", out.Reasons)
	}
	if !strings.Contains(out.Hint, "--parent-only") {
		t.Errorf("hint should spell out the bring-forward-then-bump remedy, got %q", out.Hint)
	}
	if len(out.Pushed) != 0 || out.Landed {
		t.Errorf("a refusal must publish nothing: %+v", out)
	}
	if headOf(t, main) != baseBefore {
		t.Error("main must be untouched on a refusal")
	}
	if got := pinAtRef(main, "HEAD", "sub"); got != subSha {
		t.Errorf("main's pin = %s, want it unmoved at %s", got, subSha)
	}
	if _, err := runGit(parentRemote, "rev-parse", "--verify", "--quiet", "refs/heads/feat"); err == nil {
		t.Error("feature branch must not be pushed on a refusal")
	}
}

// A rewind can be deliberate (reverting a submodule bump), so the override
// lands it — as a warning, never silently.
func TestWorktreeLand_PinRewindAllowedByFlag(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	rewindPinViaConflict(t, proj)

	code, out := runLand(t, "--path", feat, "--allow-pin-rewind")
	if code != ExitOK || !out.Landed {
		t.Fatalf("expected the override to land, got %d: %+v", code, out)
	}
	if !hasReason(out.Warnings, "--allow-pin-rewind") || !hasReason(out.Warnings, "is behind") {
		t.Errorf("an allowed rewind must still be reported: %+v", out.Warnings)
	}
	if headOf(t, main) != headOf(t, feat) {
		t.Error("main should have fast-forwarded onto the feature")
	}
}

// The window between pre-flight and the fast-forward: if another land moved the
// base branch, refuse instead of merging.
func TestWorktreeLand_BaseMovedGuard(t *testing.T) {
	proj := setupFeatureProject(t)
	main := wtPath(proj, "main")
	res := WorktreeBaseResult{
		Name: "main", Path: main, Branch: "main",
		Action: "missing", Submodules: []GitSyncSubmodule{},
	}
	before := headOf(t, main)

	got := landBaseWorktree(res, "feat", "0000000000000000000000000000000000000000")
	if got.Action != "failed" || !strings.Contains(got.Error, "moved during land") {
		t.Fatalf("expected a moved-during-land refusal, got %+v", got)
	}
	if headOf(t, main) != before {
		t.Error("the guard must fire before anything moves")
	}
}

func TestWorktreeLand_OnBaseWorktreeRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	code, out := runLand(t, "--path", wtPath(proj, "main"))
	if code != ExitFailure || !hasReason(out.Reasons, "base worktree") {
		t.Errorf("landing the base worktree should be refused, got %d: %+v", code, out.Reasons)
	}
}
