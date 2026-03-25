package cmd

import (
	"encoding/json"
	flag "github.com/spf13/pflag"
	"fmt"
)

// analyzeGitIssues examines collected git data and returns a list of issues.
// Pure function — no I/O.
func analyzeGitIssues(data GitOutput) []CheckIssue {
	var issues []CheckIssue
	root := data.Path

	// Parent repo checks
	if data.Repo.Dirty {
		issues = append(issues, CheckIssue{
			Repo:     ".",
			Severity: "error",
			Type:     "dirty",
			Message:  "parent repo has uncommitted changes",
			Fix:      fmt.Sprintf("glittering git diff --path %s", root),
		})
	}
	if data.Repo.Detached {
		issues = append(issues, CheckIssue{
			Repo:     ".",
			Severity: "error",
			Type:     "detached",
			Message:  "parent repo is in detached HEAD state",
			Fix:      fmt.Sprintf("glittering git pull --path %s", root),
		})
	}
	if data.Repo.AheadRemote > 0 && !data.Repo.HeadOnRemote {
		issues = append(issues, CheckIssue{
			Repo:     ".",
			Severity: "error",
			Type:     "unpushed",
			Message:  fmt.Sprintf("parent repo has %d unpushed commit(s)", data.Repo.AheadRemote),
			Fix:      fmt.Sprintf("glittering git push --path %s", root),
		})
	}
	if data.Repo.StashCount > 0 {
		issues = append(issues, CheckIssue{
			Repo:     ".",
			Severity: "warn",
			Type:     "stash",
			Message:  fmt.Sprintf("parent repo has %d stash entry(ies)", data.Repo.StashCount),
		})
	}
	if data.Repo.Upstream == "" && !data.Repo.Detached && data.Repo.Branch != "" {
		issues = append(issues, CheckIssue{
			Repo:     ".",
			Severity: "warn",
			Type:     "no_upstream",
			Message:  "parent repo has no upstream tracking branch",
		})
	}

	// Submodule checks
	for _, sub := range data.Submodules {
		if sub.Dirty {
			issues = append(issues, CheckIssue{
				Repo:     sub.Path,
				Severity: "error",
				Type:     "dirty",
				Message:  fmt.Sprintf("%s has uncommitted changes", sub.Path),
				Fix:      fmt.Sprintf("glittering git diff --path %s", root),
			})
		}
		if sub.Detached {
			issues = append(issues, CheckIssue{
				Repo:     sub.Path,
				Severity: "error",
				Type:     "detached",
				Message:  fmt.Sprintf("%s is in detached HEAD state", sub.Path),
				Fix:      fmt.Sprintf("glittering git pull --path %s", root),
			})
		}
		if sub.AheadRemote > 0 && !sub.HeadOnRemote {
			issues = append(issues, CheckIssue{
				Repo:     sub.Path,
				Severity: "error",
				Type:     "unpushed",
				Message:  fmt.Sprintf("%s has %d unpushed commit(s)", sub.Path, sub.AheadRemote),
				Fix:      fmt.Sprintf("glittering git push --path %s", root),
			})
		}
		if sub.StashCount > 0 {
			issues = append(issues, CheckIssue{
				Repo:     sub.Path,
				Severity: "warn",
				Type:     "stash",
				Message:  fmt.Sprintf("%s has %d stash entry(ies)", sub.Path, sub.StashCount),
			})
		}
		if sub.Upstream == "" && !sub.Detached && sub.Branch != "" {
			issues = append(issues, CheckIssue{
				Repo:     sub.Path,
				Severity: "warn",
				Type:     "no_upstream",
				Message:  fmt.Sprintf("%s has no upstream tracking branch", sub.Path),
			})
		}
		if sub.AheadParent > 0 {
			issues = append(issues, CheckIssue{
				Repo:     sub.Path,
				Severity: "warn",
				Type:     "ahead_parent",
				Message:  fmt.Sprintf("%s is %d commit(s) ahead of parent ref", sub.Path, sub.AheadParent),
				Fix:      fmt.Sprintf("glittering git commit-parent --message \"update %s submodule ref\" --path %s %s", sub.Path, root, sub.Path),
			})
		}
		if sub.BehindParent > 0 {
			issues = append(issues, CheckIssue{
				Repo:     sub.Path,
				Severity: "info",
				Type:     "behind_parent",
				Message:  fmt.Sprintf("%s is %d commit(s) behind parent ref", sub.Path, sub.BehindParent),
			})
		}
	}

	return issues
}

// buildCheckOutput constructs the CheckOutput from a path, timestamp, and issues list.
func buildCheckOutput(path string, timestamp *string, issues []CheckIssue) CheckOutput {
	if issues == nil {
		issues = []CheckIssue{}
	}
	summary := CheckSummary{}
	for _, issue := range issues {
		switch issue.Severity {
		case "error":
			summary.Errors++
		case "warn":
			summary.Warns++
		case "info":
			summary.Infos++
		}
	}
	return CheckOutput{
		Path:      path,
		Timestamp: timestamp,
		Clean:     summary.Errors == 0 && summary.Warns == 0,
		Issues:    issues,
		Summary:   summary,
	}
}

// GitCheck verifies that all repos are committed, pushed, and refs are in sync.
func GitCheck(args []string) int {
	fs := flag.NewFlagSet("git check", flag.ExitOnError)
	path := fs.String("path", ".", "repository root path")
	skipFetch := fs.Bool("skip-fetch", false, "skip fetching from remotes")
	cached := fs.Bool("cached", false, "read from cache instead of running live")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	if *cached && *skipFetch {
		logf("error: --cached and --skip-fetch are mutually exclusive\n")
		return ExitUsage
	}

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	var data GitOutput

	if *cached {
		raw, err := readCache(root, "git.json")
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		if raw == nil {
			// No cache — return clean with no data
			out := buildCheckOutput(root, nil, nil)
			outputJSON(out)
			return ExitOK
		}
		if err := json.Unmarshal(raw, &data); err != nil {
			logf("error: parsing cached git data: %v\n", err)
			return ExitFailure
		}
	} else {
		data, err = collectGitData(root, !*skipFetch)
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		writeCache(root, "git.json", data)
	}

	issues := analyzeGitIssues(data)
	out := buildCheckOutput(root, data.Timestamp, issues)

	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	if !out.Clean {
		return ExitFailure
	}
	return ExitOK
}
