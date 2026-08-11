package cmd

import (
	"fmt"
	"os"
	"path/filepath"
)

// Pin-regression detection, shared by `worktree update` and `worktree land`.
//
// A parent fast-forward says nothing about gitlinks: a tree whose pin points at
// an *older* submodule commit still fast-forwards cleanly, so landing it moves
// the base branch's pin backwards and silently reverts published submodule
// work. Nothing local flags it — the worktree and its pin agree, so status is
// clean and `git sync` reports in_sync. Only a comparison against the base
// branch surfaces it.
//
// The usual cause is resolving an `update` conflict with `git add -A`: the
// merge stages the incoming pin, but `git add -A` re-stages the gitlink at the
// submodule worktree's HEAD (git doesn't check submodules out during a merge),
// discarding it.

// pinRegression is a submodule whose pin in a worktree is not a descendant of
// the base branch's pin.
type pinRegression struct {
	Submodule  string
	Ref        string // base ref compared against
	BasePin    string
	FeaturePin string
	Kind       string // "behind" · "diverged" · "unverified"
}

// baseRefs are the refs a feature worktree must not regress against: the local
// base branch and its remote-tracking ref (either may be ahead of the other).
func baseRefs(baseBranch string) []string {
	return []string{"refs/heads/" + baseBranch, "refs/remotes/origin/" + baseBranch}
}

// detectPinRegressions reports submodules whose pin in wtPath's HEAD would move
// a base ref's pin backwards or sideways. At most one regression per submodule
// (the refs usually agree). Uninitialised submodules are skipped — there is no
// local clone to relate the two commits in.
func detectPinRegressions(wtPath string, subPaths, refs []string) []pinRegression {
	var regressions []pinRegression
	for _, sub := range subPaths {
		subDir := filepath.Join(wtPath, sub)
		if _, err := os.Stat(filepath.Join(subDir, ".git")); err != nil {
			continue
		}
		featurePin := pinAtRef(wtPath, "HEAD", sub)
		if featurePin == "" {
			continue
		}
		for _, ref := range refs {
			basePin := pinAtRef(wtPath, ref, sub)
			if basePin == "" || basePin == featurePin {
				continue
			}
			if reg, regressed := comparePins(subDir, sub, ref, basePin, featurePin); regressed {
				regressions = append(regressions, reg)
				break
			}
		}
	}
	return regressions
}

// comparePins relates a submodule's base-branch pin to a worktree's. Safe only
// when the base pin is already contained in the worktree's pin — a strict
// fast-forward of the submodule's history.
func comparePins(subDir, sub, ref, basePin, featurePin string) (pinRegression, bool) {
	reg := pinRegression{Submodule: sub, Ref: ref, BasePin: basePin, FeaturePin: featurePin}
	for _, sha := range []string{basePin, featurePin} {
		if _, err := runGit(subDir, "cat-file", "-e", sha+"^{commit}"); err != nil {
			reg.Kind = "unverified"
			return reg, true
		}
	}
	if _, err := runGit(subDir, "merge-base", "--is-ancestor", basePin, featurePin); err == nil {
		return reg, false
	}
	reg.Kind = "behind"
	if _, featureOnly := getRevListCount(subDir, basePin, featurePin); featureOnly > 0 {
		reg.Kind = "diverged"
	}
	return reg, true
}

// reason states the regression and what it would cost.
func (r pinRegression) reason() string {
	switch r.Kind {
	case "unverified":
		return fmt.Sprintf("%s: cannot compare its pin against %s — a pinned commit is missing from the clone (never pushed, or the fetch failed)",
			r.Submodule, shortRefName(r.Ref))
	case "diverged":
		return fmt.Sprintf("%s: pin %s has diverged from %s's pin %s — landing would drop that submodule work",
			r.Submodule, shortRef(r.FeaturePin), shortRefName(r.Ref), shortRef(r.BasePin))
	default:
		return fmt.Sprintf("%s: pin %s is behind %s's pin %s — landing would rewind it, silently reverting published submodule work (a `git add -A` while resolving a merge does this)",
			r.Submodule, shortRef(r.FeaturePin), shortRefName(r.Ref), shortRef(r.BasePin))
	}
}

// fix is the concrete remedy: bring the submodule up to the base's pin, then
// bump the parent's gitlink to match.
func (r pinRegression) fix(wtPath string) string {
	subDir := filepath.Join(wtPath, r.Submodule)
	if r.Kind == "unverified" {
		return fmt.Sprintf("push or fetch the submodule commit %s in %s, then re-run", shortRef(r.BasePin), subDir)
	}
	verb := "merge --ff-only"
	if r.Kind == "diverged" {
		verb = "merge"
	}
	return fmt.Sprintf("git -C %s %s %s, then: glittering git commit --parent-only --path %s %s",
		subDir, verb, shortRef(r.BasePin), wtPath, r.Submodule)
}

// shortRefName trims a full ref to how a person names it (main, origin/main).
func shortRefName(ref string) string {
	for _, prefix := range []string{"refs/heads/", "refs/remotes/"} {
		if len(ref) > len(prefix) && ref[:len(prefix)] == prefix {
			return ref[len(prefix):]
		}
	}
	return ref
}
