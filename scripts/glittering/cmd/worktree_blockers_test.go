package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Regression suite for the heal-then-classify pre-flight: the incident that
// motivated it (an unconverged gitlink deadlocking `update`'s own remedy),
// plus one test per blocker classification.

// unconvergedGitlinkViaConflict reproduces the incident: main bumps a pin in a
// commit that also conflicts, and the conflict is resolved *correctly* —
// staging only the conflicted file — so the merge's incoming pin survives into
// the merge commit while the submodule worktree stays at the old commit. The
// tree is left showing ` M sub`, which used to deadlock the documented
// "resolve, commit, re-run update" loop. Returns the new pin.
func unconvergedGitlinkViaConflict(t *testing.T, proj string) string {
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
	gitRun(t, feat, "add", "--", "PROJECT_PLAN.md")
	gitRun(t, feat, "commit", "--quiet", "--no-edit")

	// Fixture preconditions: the merge commit carries the new pin, the
	// submodule worktree is still behind it, and the parent tree shows it.
	if isClean(t, feat) {
		t.Fatal("fixture: expected the unconverged gitlink to show as dirt")
	}
	if got := pinAtRef(feat, "HEAD", "sub"); got != subSha {
		t.Fatalf("fixture: pin = %s, want %s", got, subSha)
	}
	if got := headOf(t, filepath.Join(feat, "sub")); got == subSha {
		t.Fatal("fixture: submodule worktree already at the pin")
	}
	return subSha
}

// The incident: re-running update after a correctly resolved conflict must
// converge the pin it recorded, not refuse on it.
func TestWorktreeUpdate_UnconvergedGitlinkHealed(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	subSha := unconvergedGitlinkViaConflict(t, proj)

	code, out := runUpdate(t, "--path", feat, "--skip-fetch")
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if len(out.Reasons) != 0 || len(out.Blockers) != 0 {
		t.Errorf("a healable gitlink must not refuse: %v / %+v", out.Reasons, out.Blockers)
	}
	if len(out.Submodules) != 1 || out.Submodules[0].Action != "synced" || out.Submodules[0].ToRef != subSha {
		t.Errorf("the heal must be visible in submodules[], got %+v", out.Submodules)
	}
	featSub := filepath.Join(feat, "sub")
	if got := headOf(t, featSub); got != subSha {
		t.Errorf("submodule HEAD = %s, want the pin %s", got, subSha)
	}
	if b := strings.TrimSpace(gitOut(t, featSub, "branch", "--show-current")); b != "main" {
		t.Errorf("submodule must stay on its branch, got %q (detached?)", b)
	}
	if !isClean(t, feat) {
		t.Errorf("worktree left dirty:\n%s", gitOut(t, feat, "status", "--porcelain"))
	}
}

// Lockfile-only dirt is generated churn: refused with its own code and the
// exact remedy, never lumped in with the user's work.
func TestWorktreeUpdate_StaleLockfilesRefused(t *testing.T) {
	tests := []struct {
		name  string
		dirty func(t *testing.T, feat string)
	}{
		{"tracked modified", func(t *testing.T, feat string) {
			commitFileIn(t, feat, "pubspec.lock", "old\n", "add lockfile")
			writeFileIn(t, feat, "pubspec.lock", "regenerated\n")
		}},
		{"untracked", func(t *testing.T, feat string) {
			writeFileIn(t, feat, "pubspec.lock", "regenerated\n")
		}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			proj := setupFeatureProject(t)
			feat := wtPath(proj, "feat")
			tc.dirty(t, feat)
			before := headOf(t, feat)

			code, out := runUpdate(t, "--path", feat, "--skip-fetch")
			if code != ExitFailure {
				t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
			}
			b := blockerFor(out.Blockers, BlockerStaleLockfiles)
			if b == nil {
				t.Fatalf("expected stale_lockfiles, got %+v", out.Blockers)
			}
			if hasBlocker(out.Blockers, BlockerUserChanges) {
				t.Errorf("lockfile churn must not read as user changes: %+v", out.Blockers)
			}
			if !hasReason(b.Paths, "pubspec.lock") || !strings.Contains(out.Hint, "glittering get") {
				t.Errorf("blocker should name the lockfile and the get remedy: %+v / %q", b, out.Hint)
			}
			if out.Merge.Status != "skipped" || headOf(t, feat) != before || mergeInProgress(t, feat) {
				t.Error("refused update must leave the worktree untouched")
			}
		})
	}
}

// Same classification at land time: the churn is named, nothing is published.
func TestWorktreeLand_StaleLockfilesRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	parentRemote := remoteURLOf(t, filepath.Join(proj, ".bare"))
	landableFeature(t, proj)
	writeFileIn(t, feat, "pubspec.lock", "regenerated\n")

	code, out := runLand(t, "--path", feat)
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
	}
	if !hasBlocker(out.Blockers, BlockerStaleLockfiles) || !strings.Contains(out.Hint, "glittering get") {
		t.Errorf("expected stale_lockfiles with the get remedy: %+v / %q", out.Blockers, out.Hint)
	}
	if len(out.Pushed) != 0 || out.Landed {
		t.Errorf("a refusal must publish nothing: %+v", out)
	}
	if _, err := runGit(parentRemote, "rev-parse", "--verify", "--quiet", "refs/heads/feat"); err == nil {
		t.Error("feature branch must not be pushed on a refusal")
	}
}

// Dirt confined inside a submodule is named as such — submodule and file, not
// the old blanket parent-dirt message; lockfile-only sub dirt is still churn.
func TestWorktreeUpdate_SubmoduleDirtRefused(t *testing.T) {
	tests := []struct {
		name  string
		rel   string // path inside the submodule
		want  BlockerCode
		wantP string // expected blocker path
	}{
		{"work file", "wip.txt", BlockerSubmoduleDirty, "sub/wip.txt"},
		{"lockfile", "example/pubspec.lock", BlockerStaleLockfiles, "sub/example/pubspec.lock"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			proj := setupFeatureProject(t)
			feat := wtPath(proj, "feat")
			featSub := filepath.Join(feat, "sub")
			full := filepath.Join(featSub, tc.rel)
			if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
				t.Fatalf("mkdir: %v", err)
			}
			writeFileIn(t, featSub, tc.rel, "dirt\n")
			before, subBefore := headOf(t, feat), headOf(t, featSub)

			code, out := runUpdate(t, "--path", feat, "--skip-fetch")
			if code != ExitFailure {
				t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
			}
			b := blockerFor(out.Blockers, tc.want)
			if b == nil {
				t.Fatalf("expected %s, got %+v", tc.want, out.Blockers)
			}
			if !hasReason(b.Paths, tc.wantP) || !hasReason([]string{b.Message}, "sub") {
				t.Errorf("blocker should name the submodule path %s: %+v", tc.wantP, b)
			}
			if headOf(t, feat) != before || headOf(t, featSub) != subBefore || mergeInProgress(t, feat) {
				t.Error("refused update must leave both worktrees untouched")
			}
		})
	}
}

// A submodule ahead of its pin is the user's unpinned work: refuse with the
// bump remedy, and never rewind the submodule to the pin.
func TestWorktreeUpdate_SubmoduleAheadRefused(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")
	featSub := filepath.Join(feat, "sub")
	aheadSha := commitFileIn(t, featSub, "ahead.txt", "ahead\n", "unpinned sub work")
	pinBefore := pinAtRef(feat, "HEAD", "sub")

	code, out := runUpdate(t, "--path", feat, "--skip-fetch")
	if code != ExitFailure {
		t.Fatalf("expected ExitFailure, got %d: %+v", code, out)
	}
	b := blockerFor(out.Blockers, BlockerSubmoduleAhead)
	if b == nil {
		t.Fatalf("expected submodule_ahead, got %+v", out.Blockers)
	}
	if !strings.Contains(b.Hint, "--parent-only") {
		t.Errorf("hint should spell out the pin bump, got %q", b.Hint)
	}
	if got := headOf(t, featSub); got != aheadSha {
		t.Errorf("forward-only heal must never rewind the submodule: HEAD = %s, want %s", got, aheadSha)
	}
	if got := pinAtRef(feat, "HEAD", "sub"); got != pinBefore {
		t.Errorf("the pin must be untouched: %s, want %s", got, pinBefore)
	}
}

// Land heals a healable gitlink and proceeds — the whole incident becomes a
// single land, with the heal visible in submodules[] and blockers empty in
// the JSON (never null).
func TestWorktreeLand_HealsGitlinkThenLands(t *testing.T) {
	proj := setupFeatureProject(t)
	main, feat := wtPath(proj, "main"), wtPath(proj, "feat")
	subSha := unconvergedGitlinkViaConflict(t, proj)

	var code int
	stdout := captureStdout(t, func() { code = Worktree([]string{"land", "--path", feat}) })
	var out WorktreeLandOutput
	mustJSON(t, stdout, &out)
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %+v", code, out)
	}
	if !out.Landed || !out.Success {
		t.Fatalf("expected landed+success: %+v", out)
	}
	if !strings.Contains(stdout, `"blockers": []`) {
		t.Errorf("expected \"blockers\": [] in the output, got:\n%s", stdout)
	}
	if len(out.Submodules) != 1 || out.Submodules[0].Action != "synced" || out.Submodules[0].ToRef != subSha {
		t.Errorf("the heal must be visible in submodules[], got %+v", out.Submodules)
	}
	if headOf(t, filepath.Join(feat, "sub")) != subSha {
		t.Errorf("feature submodule should be at the pin")
	}
	if headOf(t, main) != headOf(t, feat) {
		t.Error("base should have fast-forwarded onto the feature")
	}
	if !isClean(t, feat) || !isClean(t, main) {
		t.Error("both worktrees should come out clean")
	}
}

// The blockers list is part of the update JSON contract on the happy path too.
func TestWorktreeUpdate_BlockersEmptyInJSON(t *testing.T) {
	proj := setupFeatureProject(t)
	feat := wtPath(proj, "feat")

	var code int
	stdout := captureStdout(t, func() { code = Worktree([]string{"update", "--path", feat, "--skip-fetch"}) })
	if code != ExitOK {
		t.Fatalf("expected ExitOK, got %d: %s", code, stdout)
	}
	if !strings.Contains(stdout, `"blockers": []`) {
		t.Errorf("expected \"blockers\": [] in the output, got:\n%s", stdout)
	}
}

// A merge that changes a pubspec.yaml stales every dependent lockfile — update
// says so at the moment of cause, without running pub get itself.
func TestWorktreeUpdate_PubspecChangeNudgesLockfiles(t *testing.T) {
	tests := []struct {
		name     string
		rel      string
		wantHint bool
	}{
		{"pubspec change nudges", "pubspec.yaml", true},
		{"unrelated change stays quiet", "other.txt", false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			proj := setupFeatureProject(t)
			feat := wtPath(proj, "feat")
			commitFileIn(t, feat, "feature.txt", "feature\n", "feature work")
			pushScratchParentCommit(t, proj, func(s string) {
				writeFileIn(t, s, tc.rel, "dependencies changed\n")
			}, "dep bump")

			code, out := runUpdate(t, "--path", feat)
			if code != ExitOK || out.Merge.Status != "merged" {
				t.Fatalf("expected a clean merge, got %d: %+v", code, out.Merge)
			}
			gotHint := strings.Contains(out.Hint, "glittering get")
			if gotHint != tc.wantHint {
				t.Errorf("get hint present = %v, want %v (hint %q)", gotHint, tc.wantHint, out.Hint)
			}
			if tc.wantHint && !hasReason(out.Warnings, "pubspec.yaml") {
				t.Errorf("warning should name the changed pubspec, got %v", out.Warnings)
			}
			// The nudge is a hint, not an action: update must not run pub get.
			if _, err := os.Stat(filepath.Join(feat, "pubspec.lock")); err == nil {
				t.Error("update must not generate lockfiles itself")
			}
		})
	}
}
