package cmd

import (
	"encoding/json"
	"fmt"
	flag "github.com/spf13/pflag"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// worktreeList reports every worktree in the project with per-worktree status.
func worktreeList(args []string) int {
	fs := flag.NewFlagSet("worktree list", flag.ExitOnError)
	path := fs.String("path", ".", "path inside the project")
	filter := fs.String("filter", "", "filter worktrees by name or branch")
	cached := fs.Bool("cached", false, "read each worktree's cached git.json instead of live status")
	fetch := fs.Bool("fetch", false, "fetch remotes once before collecting status")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	if *cached && *fetch {
		logf("error: --cached and --fetch are mutually exclusive\n")
		return ExitUsage
	}
	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}
	proj, metas, err := discoverWorktrees(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	out := buildWorktreeList(proj, metas, parseFilter(*filter), *cached, *fetch)
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	return ExitOK
}

// buildWorktreeList assembles the list output. Stash is project-level (refs/stash
// is shared); rows are collected in parallel.
func buildWorktreeList(proj projectInfo, allMetas []worktreeMeta, filters []string, cached, fetch bool) WorktreeListOutput {
	stash := 0
	if p := stashProbePath(proj, allMetas); p != "" {
		stash = getStashCount(p)
	}
	if fetch {
		if _, err := runGitNet(proj.CommonDir, "fetch", "origin"); err != nil {
			progressf("  warning: fetch failed: %v\n", err)
		}
	}
	rows := collectWorktreeRows(proj, filterWorktrees(allMetas, filters), cached)
	if rows == nil {
		rows = []WorktreeInfo{}
	}
	return WorktreeListOutput{
		Project:    proj.ProjectName,
		ProjectDir: proj.ProjectDir,
		BaseBranch: proj.BaseBranch,
		Current:    currentName(proj, allMetas),
		StashCount: stash,
		Worktrees:  rows,
		Orphans:    findOrphanDirs(proj, allMetas),
	}
}

// findOrphanDirs scans the project root for visible directories git doesn't
// list — leftovers from failed removals (see removeWorktreeDir). Hidden
// entries (.bare, .git) and symlinks are skipped; ancestors of nested
// worktrees are live, not orphans. One level deep by design: an orphan nested
// under a live ancestor is still reachable via `worktree remove <a>/<b>`.
func findOrphanDirs(proj projectInfo, metas []worktreeMeta) []WorktreeOrphan {
	orphans := []WorktreeOrphan{}
	entries, err := os.ReadDir(proj.ProjectDir)
	if err != nil {
		return orphans
	}
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		path := filepath.Join(proj.ProjectDir, e.Name())
		if registeredOrAncestor(metas, path) {
			continue
		}
		orphans = append(orphans, WorktreeOrphan{
			Name: e.Name(),
			Path: path,
			Hint: fmt.Sprintf("glittering worktree remove %s --force", e.Name()),
		})
	}
	return orphans
}

// collectWorktreeRows builds a row per worktree with bounded parallelism,
// preserving input order (mirrors collectGitData, git.go:109).
func collectWorktreeRows(proj projectInfo, metas []worktreeMeta, cached bool) []WorktreeInfo {
	const maxJobs = 8
	type indexed struct {
		i   int
		row WorktreeInfo
	}
	ch := make(chan indexed, len(metas))
	sem := make(chan struct{}, maxJobs)
	for i, m := range metas {
		sem <- struct{}{}
		go func(i int, m worktreeMeta) {
			defer func() { <-sem }()
			ch <- indexed{i, buildWorktreeRow(proj, m, cached)}
		}(i, m)
	}
	rows := make([]WorktreeInfo, len(metas))
	for range metas {
		r := <-ch
		rows[r.i] = r.row
	}
	return rows
}

// buildWorktreeRow computes one worktree's status. Branch/Detached come from the
// live porcelain (meta); remote fields are live or cached; base/age/uninit are
// local (no network) in both modes.
func buildWorktreeRow(proj projectInfo, m worktreeMeta, cached bool) WorktreeInfo {
	row := WorktreeInfo{
		Name:     m.Name,
		Path:     m.Path,
		Branch:   m.Branch,
		Detached: m.Detached,
		Current:  m.Path == proj.CurrentPath,
	}
	if cached {
		applyCachedStatus(&row, m)
	} else if st, err := getRepoStatus(m.Path); err == nil {
		row.Dirty = st.Dirty
		row.AheadRemote = st.AheadRemote
		row.BehindRemote = st.BehindRemote
		row.HeadOnRemote = st.HeadOnRemote
		row.UntrackedCount = st.UntrackedCount
		row.LastCommit = st.LatestCommit
	}
	row.BehindBase, row.AheadBase = getRevListCount(m.Path, proj.BaseBranch, "HEAD")
	row.UninitSubmodules = len(getUninitialisedSubmodules(m.Path))
	if ts, ok := lastCommitUnix(m.Path); ok {
		row.LastCommitAgeSecs = time.Now().Unix() - ts
	} else {
		row.LastCommitAgeSecs = -1
	}
	row.Removable = !row.Dirty && row.AheadRemote == 0 && row.HeadOnRemote &&
		!row.Current && !row.Detached && row.Name != proj.BaseBranch && row.UninitSubmodules == 0
	return row
}

// applyCachedStatus fills remote-dependent fields from a worktree's git.json.
// A missing/unparseable cache marks the row Stale and leaves remote fields zero
// (so it never reads removable on untrusted data).
func applyCachedStatus(row *WorktreeInfo, m worktreeMeta) {
	raw, err := readCache(m.Path, "git.json")
	if err != nil || raw == nil {
		row.Stale = true
		return
	}
	var data GitOutput
	if err := json.Unmarshal(raw, &data); err != nil {
		row.Stale = true
		return
	}
	r := data.Repo
	row.Dirty = r.Dirty
	row.AheadRemote = r.AheadRemote
	row.BehindRemote = r.BehindRemote
	row.HeadOnRemote = r.HeadOnRemote
	row.UntrackedCount = r.UntrackedCount
	row.LastCommit = r.LatestCommit
}

// lastCommitUnix returns HEAD's commit time as a unix timestamp; ok=false when
// it can't be read (e.g. an unborn branch) so callers avoid a now-0 garbage age.
func lastCommitUnix(dir string) (int64, bool) {
	out, err := runGit(dir, "show", "-s", "--format=%ct", "HEAD")
	if err != nil || out == "" {
		return 0, false
	}
	ts, err := strconv.ParseInt(strings.TrimSpace(out), 10, 64)
	if err != nil {
		return 0, false
	}
	return ts, true
}

// stashProbePath picks a real worktree to read the shared refs/stash from
// (`git stash list` fails in the bare common dir).
func stashProbePath(proj projectInfo, metas []worktreeMeta) string {
	if proj.CurrentPath != "" {
		return proj.CurrentPath
	}
	if bw, ok := baseWorktree(metas, proj.BaseBranch); ok {
		return bw.Path
	}
	if len(metas) > 0 {
		return metas[0].Path
	}
	return ""
}

// currentName maps the current worktree path to its Name, or "".
func currentName(proj projectInfo, metas []worktreeMeta) string {
	for _, m := range metas {
		if m.Path == proj.CurrentPath {
			return m.Name
		}
	}
	return ""
}

// worktreePath prints the absolute path of a named worktree as plain stdout
// (for `cd $(glitter worktree path <name>)`); logs go to stderr.
func worktreePath(args []string) int {
	fs := flag.NewFlagSet("worktree path", flag.ExitOnError)
	path := fs.String("path", ".", "path inside the project")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	names := fs.Args()
	if len(names) != 1 {
		logf("error: worktree path requires exactly one <name>\n")
		return ExitUsage
	}
	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}
	_, metas, err := discoverWorktrees(root)
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	target, ok := resolveWorktreeTarget(metas, names[0])
	if !ok {
		logf("error: no worktree named %q\n", names[0])
		return ExitFailure
	}
	fmt.Println(target.Path)
	return ExitOK
}
