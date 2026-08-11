package cmd

import (
	"path/filepath"
	"strings"
	"testing"
)

// The base worktree is fast-forwarded to origin before anything is merged, and
// the feature worktree ends up containing the new base commit.
func TestWorktreeUpdate_BaseFastForwarded(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "PROJECT_PLAN.md", "plan v2\n")
	}, "plan v2")
	baseBefore := headOf(t, main)

	code, out := runUpdate(t, "--path", feat)
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if out.Base.Action != "fast_forwarded" || out.Base.NewCommits != 1 {
		t.Errorf("base: expected fast_forwarded (1 commit), got %+v", out.Base)
	}
	if out.Base.FromRef != baseBefore || headOf(t, main) != out.Base.ToRef {
		t.Errorf("base worktree HEAD should be at %s, got %s", out.Base.ToRef, headOf(t, main))
	}
	if out.Merge.Status != "merged" || out.Merge.CommitsIntegrated != 1 {
		t.Errorf("merge: expected merged (1 commit), got %+v", out.Merge)
	}
	if _, err := runGit(feat, "merge-base", "--is-ancestor", "main", "HEAD"); err != nil {
		t.Error("feature worktree should contain the new main commit")
	}
}

// A feature commit plus a base commit produce a real merge — the feature's own
// work survives and main is integrated.
func TestWorktreeUpdate_CleanMerge(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	featCommit := commitFileIn(t, feat, "feature.txt", "feature\n", "feature work")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "other.txt", "other\n")
	}, "main work")

	code, out := runUpdate(t, "--path", feat)
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if out.Merge.Status != "merged" {
		t.Fatalf("expected merged, got %+v", out.Merge)
	}
	if _, err := runGit(feat, "merge-base", "--is-ancestor", featCommit, "HEAD"); err != nil {
		t.Error("the feature's own commit must survive the merge")
	}
	if _, err := runGit(feat, "merge-base", "--is-ancestor", "main", "HEAD"); err != nil {
		t.Error("main must be contained after the merge")
	}
	if mergeInProgress(t, feat) {
		t.Error("a clean merge must not leave a merge in progress")
	}
}

// A conflict is left in progress with the conflicted paths reported, so the
// agent can resolve, commit and re-run.
func TestWorktreeUpdate_ConflictLeavesMergeInProgress(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	commitFileIn(t, feat, "PROJECT_PLAN.md", "feature side\n", "feature edit")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "PROJECT_PLAN.md", "main side\n")
	}, "main edit")

	code, out := runUpdate(t, "--path", feat)
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure on conflict, got %d: %+v", code, out)
	}
	if out.Merge.Status != "conflicts" {
		t.Fatalf("expected conflicts, got %+v", out.Merge)
	}
	if len(out.Merge.Conflicts) != 1 || out.Merge.Conflicts[0] != "PROJECT_PLAN.md" {
		t.Errorf("conflicts: expected [PROJECT_PLAN.md], got %v", out.Merge.Conflicts)
	}
	if !mergeInProgress(t, feat) {
		t.Error("the merge must be left in progress for the agent to resolve")
	}
	if !strings.Contains(out.Hint, "worktree update") {
		t.Errorf("hint should point back at update, got %q", out.Hint)
	}
	// Re-running while unresolved refuses rather than compounding the mess.
	code2, out2 := runUpdate(t, "--path", feat, "--skip-fetch")
	if code2 != ExitFailure || !hasReason(out2.Reasons, "merge is already in progress") {
		t.Errorf("re-run should refuse with a merge-in-progress reason, got %d %+v", code2, out2.Reasons)
	}
}

// A merge that moves a gitlink leaves the submodule worktree behind the new
// pin; update converges it, on-branch.
func TestWorktreeUpdate_MovedGitlinkConverged(t *testing.T) {
	proj := setupFeatureProject(t)
	feat, main := wtPath(proj, "feat"), wtPath(proj, "main")
	subSha := pushScratchSubCommit(t, proj, "sub", "b.txt", "sub work")
	pushScratchParentCommit(t, proj, func(s string) { bumpPinIn(t, s, "sub", subSha) }, "bump sub pin")

	code, out := runUpdate(t, "--path", feat)
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if len(out.Submodules) != 1 || out.Submodules[0].Action != "synced" {
		t.Errorf("feature submodule: expected synced, got %+v", out.Submodules)
	}
	featSub := filepath.Join(feat, "sub")
	if got := headOf(t, featSub); got != subSha {
		t.Errorf("feature submodule HEAD = %s, want the new pin %s", got, subSha)
	}
	if b := strings.TrimSpace(gitOut(t, featSub, "branch", "--show-current")); b != "main" {
		t.Errorf("submodule must stay on its branch, got %q (detached?)", b)
	}
	// The base worktree must also come out clean — an unconverged gitlink there
	// would block the next update or land.
	if !isClean(t, main) {
		t.Errorf("base worktree left dirty after its fast-forward:\n%s", gitOut(t, main, "status", "--porcelain"))
	}
	if !isClean(t, feat) {
		t.Errorf("feature worktree left dirty:\n%s", gitOut(t, feat, "status", "--porcelain"))
	}
}

// A pin rewound while resolving a conflict agrees with its submodule worktree,
// so status and `git sync` both look clean — update must still surface it,
// while the fix is local.
func TestWorktreeUpdate_PinRegressionWarned(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	rewindPinViaConflict(t, proj)

	code, out := runUpdate(t, "--path", feat, "--skip-fetch")
	if code != ExitOK {
		t.Fatalf("expected ExitOK (a rewind is a warning here), got %d: %+v", code, out)
	}
	if !hasReason(out.Warnings, "is behind") || !hasReason(out.Warnings, "sub") {
		t.Errorf("expected a pin-rewind warning naming the submodule, got %+v", out.Warnings)
	}
	if !strings.Contains(out.Hint, "--parent-only") {
		t.Errorf("hint should spell out the remedy, got %q", out.Hint)
	}
	// The trap is invisible locally — that is the whole reason for the check.
	if !isClean(t, feat) {
		t.Error("fixture check: the rewound worktree should look clean")
	}
}

// The conflict hint must name the `git add -A` trap that causes the rewind.
func TestWorktreeUpdate_ConflictHintWarnsAboutStaging(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	commitFileIn(t, feat, "PROJECT_PLAN.md", "feature side\n", "feature edit")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "PROJECT_PLAN.md", "main side\n")
	}, "main edit")

	_, out := runUpdate(t, "--path", feat)
	if !strings.Contains(out.Hint, "git add -A") {
		t.Errorf("conflict hint should warn about `git add -A`, got %q", out.Hint)
	}
}

// Uncommitted work in the feature worktree is never merged over.
func TestWorktreeUpdate_DirtyFeatureRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "other.txt", "other\n")
	}, "main work")
	writeFileIn(t, feat, "wip.txt", "wip\n")
	before := headOf(t, feat)

	code, out := runUpdate(t, "--path", feat)
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
	}
	if !hasReason(out.Reasons, "uncommitted changes") || !hasReason(out.Reasons, "wip.txt") {
		t.Errorf("expected a reason naming wip.txt, got %v", out.Reasons)
	}
	if out.Merge.Status != "skipped" {
		t.Errorf("no merge should have been attempted, got %+v", out.Merge)
	}
	if headOf(t, feat) != before || mergeInProgress(t, feat) {
		t.Error("refused update must leave the worktree untouched")
	}
}

// A dirty base worktree is a warning, not a failure: its fast-forward is
// skipped and the feature integrates the base's current tip.
func TestWorktreeUpdate_DirtyBaseSkipped(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "other.txt", "other\n")
	}, "main work")
	writeFileIn(t, main, "local.txt", "local\n")
	baseBefore := headOf(t, main)

	code, out := runUpdate(t, "--path", feat)
	if code != ExitOK {
		t.Fatalf("expected ExitOK (a dirty base is a warning), got %d: %+v", code, out)
	}
	if out.Base.Action != "skipped_dirty" {
		t.Errorf("base: expected skipped_dirty, got %+v", out.Base)
	}
	if !hasReason(out.Warnings, "uncommitted changes") {
		t.Errorf("expected a warning about the dirty base, got %v", out.Warnings)
	}
	if headOf(t, main) != baseBefore {
		t.Error("dirty base worktree must not be fast-forwarded")
	}
	if out.Merge.Status != "up_to_date" {
		t.Errorf("feature already has the base tip, expected up_to_date, got %+v", out.Merge)
	}
}

func TestWorktreeUpdate_UpToDateNoOp(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	before := headOf(t, feat)

	code, out := runUpdate(t, "--path", feat)
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if out.Merge.Status != "up_to_date" || out.Merge.CommitsIntegrated != 0 {
		t.Errorf("expected up_to_date no-op, got %+v", out.Merge)
	}
	if out.Base.Action != "up_to_date" {
		t.Errorf("base: expected up_to_date, got %+v", out.Base)
	}
	if headOf(t, feat) != before {
		t.Error("a no-op update must not move HEAD")
	}
}

// Run on the base worktree itself, update degrades to the base fast-forward.
func TestWorktreeUpdate_OnBaseWorktreeDegrades(t *testing.T) {
	proj := setupFeatureProject(t)
	main := wtPath(proj, "main")
	pushScratchParentCommit(t, proj, func(s string) {
		writeFileIn(t, s, "other.txt", "other\n")
	}, "main work")

	code, out := runUpdate(t, "--path", main)
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if out.Base.Action != "fast_forwarded" {
		t.Errorf("base: expected fast_forwarded, got %+v", out.Base)
	}
	if out.Merge.Status != "skipped" {
		t.Errorf("no merge on the base worktree, got %+v", out.Merge)
	}
	if !hasReason(out.Warnings, "base worktree") {
		t.Errorf("expected a warning explaining the degrade, got %v", out.Warnings)
	}
}

func TestWorktreeUpdate_OutsideWorktree(t *testing.T) {
	proj := setupFeatureProject(t)
	if code := Worktree([]string{"update", "--path", proj}); code != ExitUsage {
		t.Errorf("--path at the project root should be ExitUsage, got %d", code)
	}
}
