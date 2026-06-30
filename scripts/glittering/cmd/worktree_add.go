package cmd

import (
	"fmt"
	flag "github.com/spf13/pflag"
	"os"
	"path/filepath"
	"strings"
)

// worktreeAdd creates a worktree, then best-effort seeds it (submodules, cache,
// pub get) so it is immediately usable. Only the `git worktree add` itself is
// fatal; later steps degrade to warnings + Success=false / ExitPartial.
func worktreeAdd(args []string) int {
	fs := flag.NewFlagSet("worktree add", flag.ExitOnError)
	path := fs.String("path", ".", "path inside the project")
	from := fs.String("from", "", "base ref for a new branch (default: project base branch)")
	noGet := fs.Bool("no-get", false, "skip pub get")
	noShare := fs.Bool("no-share-objects", false, "clone submodules fresh instead of sharing main's objects")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	names := fs.Args()
	if len(names) != 1 {
		logf("error: worktree add requires exactly one <name>\n")
		return ExitUsage
	}
	name := names[0]
	if strings.HasPrefix(*from, "-") {
		logf("error: invalid --from ref %q\n", *from)
		return ExitUsage
	}
	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}
	if err := validateWorktreeName(name); err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}
	proj, metas, err := discoverWorktrees(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	// Collision pre-check (defence-in-depth; validateWorktreeName already bars "..").
	target := filepath.Join(proj.ProjectDir, name)
	if !strings.HasPrefix(filepath.Clean(target)+string(filepath.Separator), filepath.Clean(proj.ProjectDir)+string(filepath.Separator)) {
		logf("error: worktree name escapes the project directory\n")
		return ExitUsage
	}
	if _, err := os.Stat(target); err == nil {
		logf("error: %s already exists\n", target)
		return ExitUsage
	}
	if _, exists := resolveWorktreeTarget(metas, name); exists {
		logf("error: a worktree named %q already exists\n", name)
		return ExitUsage
	}

	out := WorktreeAddOutput{
		Name: name, Path: target, Base: proj.BaseBranch, Success: true,
		Warnings: []string{}, PubGet: []PubPackageResult{},
	}

	// Step 4 — git worktree add (fatal transaction boundary).
	branch, created, addErr := runWorktreeAdd(proj, target, name, *from)
	if addErr != nil {
		out.Success = false
		out.Warnings = append(out.Warnings, addErr.Error())
		outputJSON(out)
		return ExitFailure
	}
	out.Branch, out.CreatedBranch = branch, created

	// Step 5 — submodule init (object sharing where possible).
	expected, inited, subWarnings := seedSubmodules(proj, metas, target, *noShare)
	out.SubmodulesExpected, out.SubmodulesInitialised = expected, inited
	out.Warnings = append(out.Warnings, subWarnings...)

	// Step 6 — seed test/analyze/stats cache from the base worktree.
	if bw, ok := baseWorktree(metas, proj.BaseBranch); ok {
		if n, err := copyCacheTree(bw.Path, target); err != nil {
			out.Warnings = append(out.Warnings, fmt.Sprintf("cache seed failed: %v", err))
		} else {
			out.CacheSeeded = n > 0
		}
	} else {
		out.Warnings = append(out.Warnings, "no base worktree to seed cache from")
	}

	// Step 7 — recompute git.json locally (no fetch; remote refs are shared).
	if data, err := collectGitData(target, false); err == nil {
		writeCache(target, "git.json", data)
	}

	// Guard: an uninitialised submodule is misreported as clean, so never present
	// a half-built worktree as healthy.
	if uninit := getUninitialisedSubmodules(target); len(uninit) > 0 {
		out.Success = false
		out.Warnings = append(out.Warnings,
			fmt.Sprintf("%d submodule(s) not initialised: %s", len(uninit), strings.Join(uninit, ", ")))
	}

	// Step 8 — pub get so the worktree is buildable.
	if !*noGet {
		out.PubGet = runWorktreePubGet(target)
		for _, r := range out.PubGet {
			if r.Status != "pass" {
				out.Success = false
				break
			}
		}
	}

	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if out.Success {
		return ExitOK
	}
	return ExitPartial
}

// runWorktreeAdd checks out an existing branch (local, then remote-tracking) or
// creates a new one off base/--from. Returns the branch and whether it was new.
func runWorktreeAdd(proj projectInfo, target, name, from string) (branch string, created bool, err error) {
	cd := proj.CommonDir
	if _, e := runGit(cd, "show-ref", "--verify", "--quiet", "refs/heads/"+name); e == nil {
		if from != "" {
			progressf("  note: --from ignored; branch %q already exists\n", name)
		}
		if _, e := runGit(cd, "worktree", "add", target, name); e != nil {
			return "", false, fmt.Errorf("git worktree add failed: %v", e)
		}
		return name, false, nil
	}
	if _, e := runGit(cd, "show-ref", "--verify", "--quiet", "refs/remotes/origin/"+name); e == nil {
		if _, e := runGit(cd, "worktree", "add", "--track", "-b", name, target, "origin/"+name); e != nil {
			return "", false, fmt.Errorf("git worktree add failed: %v", e)
		}
		return name, true, nil
	}
	base := from
	if base == "" {
		base = proj.BaseBranch
	}
	if _, e := runGit(cd, "rev-parse", "--verify", "--quiet", base+"^{commit}"); e != nil {
		return "", false, fmt.Errorf("base ref %q not found", base)
	}
	if _, e := runGit(cd, "worktree", "add", "-b", name, target, base); e != nil {
		return "", false, fmt.Errorf("git worktree add failed: %v", e)
	}
	return name, true, nil
}

// seedSubmodules initialises the new worktree's submodules in parallel, sharing
// objects from the base worktree's per-submodule store via --reference
// --dissociate (fast, then self-contained) when that store exists; otherwise a
// plain clone. `--reference-if-able` does not exist for `submodule update`, so
// we stat the ref first.
//
// Two phases: a single local `submodule init` writes all config (so the parallel
// updates don't contend on config.lock), then per-submodule `submodule update`
// runs concurrently — distinct module dirs + working trees make it lock-safe
// (verified). Without parallelism, a large superproject (e.g. 18 submodules)
// takes minutes; the network ref-negotiation per submodule is the bottleneck.
func seedSubmodules(proj projectInfo, metas []worktreeMeta, target string, noShare bool) (expected, inited int, warnings []string) {
	subs, err := getSubmodulePaths(target)
	if err != nil || len(subs) == 0 {
		return 0, 0, nil
	}
	expected = len(subs)

	// Phase 1: register all submodules locally (single config write).
	if _, e := runGit(target, "submodule", "init"); e != nil {
		warnings = append(warnings, fmt.Sprintf("submodule init: %v", e))
	}

	mainGitDir := ""
	if bw, ok := baseWorktree(metas, proj.BaseBranch); ok && !noShare {
		if gd, e := runGit(bw.Path, "rev-parse", "--path-format=absolute", "--git-dir"); e == nil {
			mainGitDir = gd
		}
	}

	// Phase 2: clone+checkout each submodule concurrently.
	const maxJobs = 8
	type res struct {
		ok   bool
		warn string
	}
	ch := make(chan res, len(subs))
	sem := make(chan struct{}, maxJobs)
	for _, sub := range subs {
		sem <- struct{}{}
		go func(sub string) {
			defer func() { <-sem }()
			cmd := []string{"submodule", "update", "--recursive"}
			if mainGitDir != "" {
				ref := filepath.Join(mainGitDir, "modules", sub)
				if _, e := os.Stat(ref); e == nil {
					cmd = append(cmd, "--reference", ref, "--dissociate")
				}
			}
			cmd = append(cmd, "--", sub)
			if _, e := runGitNet(target, cmd...); e != nil {
				ch <- res{warn: fmt.Sprintf("submodule %s: %v", sub, e)}
			} else {
				ch <- res{ok: true}
			}
		}(sub)
	}
	for range subs {
		if r := <-ch; r.ok {
			inited++
		} else {
			warnings = append(warnings, r.warn)
		}
	}
	return expected, inited, warnings
}

// runWorktreePubGet runs pub get across the new worktree's packages, capturing
// per-package results (does not call pubCommand, which writes its own stdout).
func runWorktreePubGet(target string) []PubPackageResult {
	packages, err := discoverPackages(target, nil)
	if err != nil {
		return []PubPackageResult{}
	}
	results := make([]PubPackageResult, 0, len(packages))
	for _, pkg := range packages {
		results = append(results, runPubCommand(target, pkg.Path, pkg.Type, "get"))
	}
	return results
}
