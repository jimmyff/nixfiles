package cmd

import (
	"fmt"
	"strings"
)

// landPreflightResult is every reason a land must be refused, collected in one
// pass so the caller reports the full list instead of one blocker at a time.
type landPreflightResult struct {
	Blockers []Blocker
	Reasons  []string // derived from Blockers
	Warnings []string
	Hint     string
}

// landPreflight collects every blocker a land must be refused on. Assumes both
// worktrees were already healed (preflightWorktree) and that `data` was
// collected afterwards, so its ahead/behind counts are what the push phase
// will act on. Pin regressions are demoted to warnings when allowPinRewind.
func landPreflight(proj projectInfo, target, base worktreeMeta, data GitOutput, allowPinRewind bool, pre, basePre preflightResult) landPreflightResult {
	var res landPreflightResult
	blockers := append(append([]Blocker{}, pre.Blockers...), basePre.Blockers...)

	// Containment: the base branch only ever moves to a commit that provably
	// contains it — local and remote alike.
	for _, ref := range baseRefs(proj.BaseBranch) {
		if _, err := runGit(target.Path, "rev-parse", "--verify", "--quiet", ref); err != nil {
			continue // no such ref yet — nothing to contain
		}
		if _, err := runGit(target.Path, "merge-base", "--is-ancestor", ref, "HEAD"); err != nil {
			blockers = append(blockers, Blocker{
				Repo: ".", Code: BlockerNotContained,
				Message: fmt.Sprintf("%s does not contain %s — run `glittering worktree update` first",
					target.Branch, strings.TrimPrefix(ref, "refs/")),
				Hint: fmt.Sprintf("glittering worktree update --path %s", target.Path),
			})
		}
	}

	// Containment covers the parent's history, not its gitlinks: a tree that
	// rewound a pin still fast-forwards, so check the pins themselves.
	for _, reg := range detectPinRegressions(target.Path, submodulePathsOf(data.Submodules), baseRefs(proj.BaseBranch)) {
		if allowPinRewind {
			res.Warnings = append(res.Warnings, "--allow-pin-rewind: "+reg.reason())
			continue
		}
		blockers = append(blockers, Blocker{
			Repo: ".", Code: BlockerPinRewind,
			Message: reg.reason() + " — pass --allow-pin-rewind if the revert is deliberate",
			Paths:   []string{reg.Submodule},
			Hint:    reg.fix(target.Path),
		})
	}

	// Pushes that would be rejected, caught before anything is published.
	if data.Repo.AheadRemote > 0 && data.Repo.BehindRemote > 0 {
		blockers = append(blockers, Blocker{
			Repo: ".", Code: BlockerRemoteDiverged,
			Message: fmt.Sprintf("%s has diverged from %s (%d ahead / %d behind) — integrate it before landing",
				target.Branch, data.Repo.Upstream, data.Repo.AheadRemote, data.Repo.BehindRemote),
		})
	}
	for _, sub := range data.Submodules {
		switch {
		case sub.AheadRemote > 0 && sub.BehindRemote > 0:
			blockers = append(blockers, Blocker{
				Repo: ".", Code: BlockerRemoteDiverged, Paths: []string{sub.Path},
				Message: fmt.Sprintf(
					"%s has diverged from %s (%d ahead / %d behind) — another worktree pushed the same submodule branch; merge %s in %s, bump the pin with `glittering git commit --parent-only --path %s`, then re-run",
					sub.Path, sub.Upstream, sub.AheadRemote, sub.BehindRemote, sub.Upstream, sub.Path, target.Path),
			})
		case !sub.HeadOnRemote && (sub.Upstream == "" || sub.Branch == ""):
			blockers = append(blockers, Blocker{
				Repo: ".", Code: BlockerNoUpstream, Paths: []string{sub.Path},
				Message: fmt.Sprintf(
					"%s has commits that are on no remote and no upstream to push to — push it manually first", sub.Path),
			})
		}
	}

	// The base worktree's branch is about to be fast-forwarded under it.
	// (When it is on the wrong branch its dirt went unchecked — the heal is
	// gated on the branch — but this blocker stops the land regardless.)
	if base.Branch != proj.BaseBranch {
		blockers = append(blockers, Blocker{
			Repo: base.Name, Code: BlockerBaseNotReady,
			Message: fmt.Sprintf("base worktree %s is not on %s", base.Name, proj.BaseBranch),
		})
	}

	res.Blockers = blockers
	res.Reasons = blockerReasons(blockers)
	res.Hint = firstHint(blockers)
	return res
}
