package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const worktreeHelpText = `glittering worktree — manage git worktrees in a bare-repo project layout

Subcommands:
  list           List all worktrees with per-worktree git status (default)
  add <name>     Create a worktree (submodule init, cache seed, pub get)
  update         Merge the base branch into this worktree (base ff + pin sync)
  land           Push this worktree and fast-forward the base branch onto it
  remove <name>  Remove a worktree (safety-gated)
  prune          Remove merged-and-pushed worktrees
  path <name>    Print the absolute path of a named worktree (plain text)

Common flags:
  -path string    path inside the project (default ".")
  -v, --verbose   show progress logs

Run 'glittering worktree <subcommand> -help' for subcommand-specific flags.
`

// Worktree dispatches to worktree subcommands.
func Worktree(args []string) int {
	if len(args) == 0 {
		return worktreeList(args)
	}
	switch args[0] {
	case "-help", "--help", "help":
		fmt.Fprint(os.Stderr, worktreeHelpText)
		return ExitOK
	case "list":
		return worktreeList(args[1:])
	case "add":
		return worktreeAdd(args[1:])
	case "update":
		return worktreeUpdate(args[1:])
	case "land":
		return worktreeLand(args[1:])
	case "remove":
		return worktreeRemove(args[1:])
	case "prune":
		return worktreePrune(args[1:])
	case "path":
		return worktreePath(args[1:])
	default:
		// A leading flag (e.g. `worktree --cached`) means bare list; anything
		// else is a mistyped subcommand.
		if strings.HasPrefix(args[0], "-") {
			return worktreeList(args)
		}
		logf("error: unknown worktree subcommand: %s\n", args[0])
		fmt.Fprint(os.Stderr, worktreeHelpText)
		return ExitUsage
	}
}

// --- Shared discovery (the spine) ---

// projectInfo describes the bare-repo project containing a given --path.
type projectInfo struct {
	CommonDir   string // absolute path to the shared git dir (.bare)
	ProjectDir  string // parent of CommonDir (~/projects/<name>)
	ProjectName string
	BaseBranch  string // the bare repo's default branch (usually "main")
	CurrentPath string // abs path of the worktree containing --path, "" if bare/root
}

// worktreeMeta is one parsed entry from `git worktree list --porcelain`.
type worktreeMeta struct {
	Name     string // path relative to ProjectDir ("main", "feat/foo")
	Path     string // absolute
	Branch   string // "" when detached
	Head     string // HEAD sha
	Detached bool
}

// discoverWorktrees resolves the project + every worktree from any --path inside
// it (a worktree, the project root, or the bare dir).
func discoverWorktrees(root string) (projectInfo, []worktreeMeta, error) {
	commonDir, err := resolveCommonDir(root)
	if err != nil {
		return projectInfo{}, nil, err
	}
	projectDir := filepath.Dir(commonDir)
	proj := projectInfo{
		CommonDir:   commonDir,
		ProjectDir:  projectDir,
		ProjectName: filepath.Base(projectDir),
		BaseBranch:  resolveBaseBranch(commonDir),
		CurrentPath: currentWorktree(root),
	}
	out, err := runGit(commonDir, "worktree", "list", "--porcelain")
	if err != nil {
		return proj, nil, fmt.Errorf("listing worktrees: %w", err)
	}
	return proj, parseWorktreePorcelain(out, projectDir), nil
}

// resolveCommonDir returns the absolute shared git dir for root, or an error
// when root is not a git repository. Works from a worktree, project root, or
// the bare dir.
func resolveCommonDir(root string) (string, error) {
	out, err := runGit(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
	if err != nil || out == "" {
		return "", fmt.Errorf("not a git repository: %s", root)
	}
	return out, nil
}

// resolveBaseBranch reads the bare repo's default branch (its HEAD symref).
func resolveBaseBranch(commonDir string) string {
	if b, err := runGit(commonDir, "symbolic-ref", "--short", "HEAD"); err == nil && b != "" {
		return b
	}
	return "main"
}

// currentWorktree returns the absolute toplevel of the worktree containing root,
// or "" when root is the bare dir / project root (no working tree there).
func currentWorktree(root string) string {
	if top, err := runGit(root, "rev-parse", "--show-toplevel"); err == nil {
		return top
	}
	return ""
}

// parseWorktreePorcelain parses `git worktree list --porcelain`, skipping the
// bare entry. Pure — unit-tested. Name is each worktree's path relative to
// projectDir (git emits symlink-resolved absolute paths, and projectDir is
// itself derived from git, so Rel is clean).
func parseWorktreePorcelain(out, projectDir string) []worktreeMeta {
	var metas []worktreeMeta
	var cur worktreeMeta
	var have, bare bool
	flush := func() {
		if have && !bare {
			metas = append(metas, cur)
		}
		cur, have, bare = worktreeMeta{}, false, false
	}
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimRight(line, "\r")
		switch {
		case line == "":
			flush()
		case strings.HasPrefix(line, "worktree "):
			p := strings.TrimPrefix(line, "worktree ")
			cur.Path = p
			if rel, err := filepath.Rel(projectDir, p); err == nil {
				cur.Name = rel
			} else {
				cur.Name = filepath.Base(p)
			}
			have = true
		case strings.HasPrefix(line, "HEAD "):
			cur.Head = strings.TrimPrefix(line, "HEAD ")
		case strings.HasPrefix(line, "branch "):
			cur.Branch = strings.TrimPrefix(strings.TrimPrefix(line, "branch "), "refs/heads/")
		case line == "detached":
			cur.Detached = true
		case line == "bare":
			bare = true
		}
	}
	flush()
	return metas
}

// filterWorktrees keeps worktrees whose Name or Branch substring-matches a filter.
func filterWorktrees(metas []worktreeMeta, filters []string) []worktreeMeta {
	if len(filters) == 0 {
		return metas
	}
	var out []worktreeMeta
	for _, m := range metas {
		for _, f := range filters {
			if strings.Contains(m.Name, f) || (m.Branch != "" && strings.Contains(m.Branch, f)) {
				out = append(out, m)
				break
			}
		}
	}
	return out
}

// resolveWorktreeTarget finds a worktree by Name, then by Branch.
func resolveWorktreeTarget(metas []worktreeMeta, name string) (worktreeMeta, bool) {
	for _, m := range metas {
		if m.Name == name {
			return m, true
		}
	}
	for _, m := range metas {
		if m.Branch != "" && m.Branch == name {
			return m, true
		}
	}
	return worktreeMeta{}, false
}

// registeredOrAncestor reports whether path is a registered worktree or an
// ancestor of one — names nest ("feat/foo" lives under "feat"), so a parent
// dir of a live worktree must never read as an orphan.
func registeredOrAncestor(metas []worktreeMeta, path string) bool {
	for _, m := range metas {
		if m.Path == path || strings.HasPrefix(m.Path, path+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

// isOrphanDir reports whether path is a plain directory inside the project
// that git doesn't know: not the project root or bare dir, not a registered
// worktree or an ancestor of one, and a real dir (os.Lstat — a file or
// symlink is never an orphan). Exact string comparison is safe: metas come
// symlink-resolved from git and ProjectDir derives from the same git output.
func isOrphanDir(proj projectInfo, metas []worktreeMeta, path string) bool {
	if path == proj.ProjectDir || path == proj.CommonDir {
		return false
	}
	if registeredOrAncestor(metas, path) {
		return false
	}
	info, err := os.Lstat(path)
	return err == nil && info.IsDir()
}

// validateWorktreeName rejects empty/absolute/traversing names and names that
// aren't valid git branch refs.
func validateWorktreeName(name string) error {
	if name == "" {
		return fmt.Errorf("worktree name required")
	}
	if filepath.IsAbs(name) || strings.Contains(name, "..") || strings.HasPrefix(name, "-") {
		return fmt.Errorf("invalid worktree name %q", name)
	}
	if _, err := runGit(".", "check-ref-format", "refs/heads/"+name); err != nil {
		return fmt.Errorf("invalid branch name %q", name)
	}
	return nil
}

// resolveWorktreeCommand resolves the project and the worktree containing
// --path, for the commands that act on "the worktree you are in" (update,
// land). Logs its own diagnostics; ExitOK means the target is usable.
func resolveWorktreeCommand(path string) (projectInfo, []worktreeMeta, worktreeMeta, int) {
	root, err := resolveRoot(path)
	if err != nil {
		logf("error: %v\n", err)
		return projectInfo{}, nil, worktreeMeta{}, ExitUsage
	}
	proj, metas, err := discoverWorktrees(root)
	if err != nil {
		logf("error: %v\n", err)
		return projectInfo{}, nil, worktreeMeta{}, ExitFailure
	}
	target, ok := currentWorktreeMeta(proj, metas)
	if !ok {
		logf("error: --path must be inside a worktree (%s has no working tree — pass a worktree path)\n", root)
		return proj, metas, worktreeMeta{}, ExitUsage
	}
	return proj, metas, target, ExitOK
}

// currentWorktreeMeta returns the worktree containing --path. False when --path
// resolved to the project root or the bare dir (no working tree there).
func currentWorktreeMeta(proj projectInfo, metas []worktreeMeta) (worktreeMeta, bool) {
	if proj.CurrentPath == "" {
		return worktreeMeta{}, false
	}
	for _, m := range metas {
		if m.Path == proj.CurrentPath {
			return m, true
		}
	}
	return worktreeMeta{}, false
}

// baseWorktree returns the worktree on the project's base branch (usually main).
func baseWorktree(metas []worktreeMeta, baseBranch string) (worktreeMeta, bool) {
	for _, m := range metas {
		if m.Branch == baseBranch || m.Name == baseBranch {
			return m, true
		}
	}
	return worktreeMeta{}, false
}
