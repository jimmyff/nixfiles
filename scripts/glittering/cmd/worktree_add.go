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
	noHook := fs.Bool("no-hook", false, "skip the worktree/on-add hook")
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

	// Step 9 — on-add hooks (global user-level + project base-worktree copy; non-fatal).
	if bw, ok := baseWorktree(metas, proj.BaseBranch); ok {
		status, warns := runOnAddHook(bw.Path, target, proj.ProjectDir, *noHook)
		out.OnAddHook = status
		out.Warnings = append(out.Warnings, warns...)
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
// After each update the submodule is reattached to the branch containing its
// pinned commit (preferring main), so the worktree isn't left on detached HEAD.
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
				reattachSubmoduleBranch(filepath.Join(target, sub))
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

// reattachSubmoduleBranch moves a freshly-updated submodule off detached HEAD
// onto the branch that contains its pinned commit (preferring main), staying AT
// the pin. Mirrors the dev-setup reattach: never origin/HEAD (a stale 'master'
// can have drifted from the pin). Best-effort — leaves detached on any failure.
func reattachSubmoduleBranch(subDir string) {
	pin, err := runGit(subDir, "rev-parse", "HEAD")
	if err != nil || pin == "" {
		return
	}
	branch := branchForCommit(subDir, pin)
	if branch == "" {
		return // no branch contains the pin; leave detached
	}
	if _, e := runGit(subDir, "show-ref", "--verify", "--quiet", "refs/heads/"+branch); e == nil {
		runGit(subDir, "checkout", "-q", branch)
	} else if _, e := runGit(subDir, "checkout", "-q", "-b", branch, pin); e == nil {
		runGit(subDir, "branch", "-q", "--set-upstream-to=origin/"+branch, branch)
	}
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

// globalHookPath returns the user-level on-add hook path
// ($XDG_CONFIG_HOME/glittering/hooks/worktree/on-add, defaulting to ~/.config),
// or "" if no home dir can be resolved. This hook runs for every project.
func globalHookPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "glittering", "hooks", "worktree", "on-add")
}

// runOnAddHook runs the worktree on-add hooks in order — the global (user-level)
// hook first, then the project's own (from the base worktree's copy, never the
// new worktree's, so a checked-out feature branch can't inject one) — and
// returns the aggregate status plus any warnings. cwd for each is the new
// worktree; each receives the GLITTER_* env vars. Non-fatal: failures are
// returned as warnings and never flip Success.
func runOnAddHook(basePath, target, projectDir string, skip bool) (status string, warnings []string) {
	hooks := []struct{ scope, path string }{
		{"global", globalHookPath()},
		{"project", filepath.Join(basePath, ".glittering", "hooks", "worktree", "on-add")},
	}
	for _, h := range hooks {
		s, w := runOneOnAddHook(h.scope, h.path, target, basePath, projectDir, skip)
		status = worseHookStatus(status, s)
		if w != "" {
			warnings = append(warnings, w)
		}
	}
	return status, warnings
}

// runOneOnAddHook runs a single on-add hook file, returning one of
// "" | ok | failed | skipped | not_executable and an optional scope-labelled
// warning. A missing hook is the silent common case.
func runOneOnAddHook(scope, hookPath, target, basePath, projectDir string, skip bool) (status, warning string) {
	if hookPath == "" {
		return "", ""
	}
	info, err := os.Stat(hookPath)
	if err != nil {
		if os.IsNotExist(err) {
			return "", "" // common case: no hook
		}
		return "", fmt.Sprintf("cannot stat %s on-add hook: %v", scope, err)
	}
	if skip {
		return "skipped", ""
	}
	if info.IsDir() {
		return "failed", fmt.Sprintf("%s on-add hook is a directory (not supported): %s", scope, hookPath)
	}
	if info.Mode()&0111 == 0 {
		return "not_executable", fmt.Sprintf("%s on-add hook exists but is not executable: %s", scope, hookPath)
	}
	env := []string{
		"GLITTER_WORKTREE_PATH=" + target,
		"GLITTER_BASE_WORKTREE=" + basePath,
		"GLITTER_PROJECT_DIR=" + projectDir,
	}
	stdout, stderr, err := runCommandEnv(target, hookTimeout, env, hookPath)
	if err != nil {
		detail := strings.TrimSpace(stderr)
		if detail == "" {
			detail = strings.TrimSpace(stdout)
		}
		if len(detail) > 400 {
			detail = detail[:400] + "…"
		}
		return "failed", fmt.Sprintf("%s on-add hook failed: %v: %s", scope, err, detail)
	}
	progressPrint(stdout) // verbose-only; runCommand buffers, no streaming
	return "ok", ""
}

// worseHookStatus folds two hook statuses into the more severe one:
// failed > not_executable > skipped > ok > "" (absent).
func worseHookStatus(a, b string) string {
	rank := map[string]int{"": 0, "ok": 1, "skipped": 2, "not_executable": 3, "failed": 4}
	if rank[b] > rank[a] {
		return b
	}
	return a
}
