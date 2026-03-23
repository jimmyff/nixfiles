package cmd

import (
	"flag"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Matches: "severity - file:line:col - message - code"
var analyzePattern = regexp.MustCompile(`^\s*(info|warning|error)\s+-\s+(.+):(\d+):(\d+)\s+-\s+(.+)\s+-\s+(\S+)\s*$`)

// Analyze runs dart analyze across discovered packages.
func Analyze(args []string) int {
	fs := flag.NewFlagSet("analyze", flag.ExitOnError)
	path := fs.String("path", ".", "workspace root path")
	filter := fs.String("filter", "", "comma-separated package name filters")
	cached := fs.Bool("cached", false, "read from cache instead of running live")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Cached mode: return cache file or empty output
	if *cached {
		data, err := readCache(root, "analyze.json")
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		if data != nil {
			os.Stdout.Write(data)
			return ExitOK
		}
		out := AnalyzeOutput{Packages: []AnalyzePackageResult{}}
		if err := outputJSON(out); err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		return ExitOK
	}

	filters := parseFilter(*filter)
	packages, err := discoverPackages(root, filters)
	if err != nil {
		logf("error: discovery failed: %v\n", err)
		return ExitFailure
	}

	logf("charm: analyzing %d packages\n", len(packages))

	session, err := createSession()
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if err := ensureSessionSubdir(session, "analyze"); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	var results []AnalyzePackageResult
	for _, pkg := range packages {
		result := runAnalyzePackage(root, session, pkg.Path)
		results = append(results, result)
	}

	summary := AnalyzeSummary{TotalPackages: len(results)}
	for _, r := range results {
		switch r.Status {
		case "pass":
			summary.PassedPackages++
		case "fail":
			summary.FailedPackages++
		case "error":
			summary.ErrorPackages++
		}
		summary.TotalErrors += r.Errors
		summary.TotalWarnings += r.Warnings
		summary.TotalInfos += r.Infos
	}

	out := AnalyzeOutput{
		Timestamp: nowTimestamp(),
		Session:   session,
		Packages:  results,
		Summary:   summary,
	}
	if out.Packages == nil {
		out.Packages = []AnalyzePackageResult{}
	}
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	writeCache(root, "analyze.json", out)

	if summary.FailedPackages > 0 || summary.ErrorPackages > 0 {
		return ExitFailure
	}
	return ExitOK
}

func runAnalyzePackage(root, session, pkgPath string) AnalyzePackageResult {
	result := AnalyzePackageResult{Path: pkgPath}
	pkgDir := filepath.Join(root, pkgPath)

	logf("  analyzing %s...", pkgPath)

	stdout, stderr, err := runCommand(pkgDir, 120*time.Second, "dart", "analyze")
	combined := stdout + "\n" + stderr

	// Parse issues from output
	var issues []AnalyzeIssue
	for _, line := range strings.Split(combined, "\n") {
		matches := analyzePattern.FindStringSubmatch(line)
		if matches == nil {
			continue
		}
		lineNum, _ := strconv.Atoi(matches[3])
		col, _ := strconv.Atoi(matches[4])
		issues = append(issues, AnalyzeIssue{
			Severity: matches[1],
			Message:  strings.TrimSpace(matches[5]),
			File:     matches[2],
			Line:     lineNum,
			Column:   col,
			Code:     matches[6],
		})
	}

	for _, issue := range issues {
		switch issue.Severity {
		case "error":
			result.Errors++
		case "warning":
			result.Warnings++
		case "info":
			result.Infos++
		}
	}

	if err != nil && result.Errors == 0 && len(issues) == 0 {
		result.Status = "error"
		result.Error = strings.TrimSpace(stderr)
		logf(" error\n")
		return result
	}

	if result.Errors > 0 || result.Warnings > 0 {
		result.Status = "fail"
		logf(" %d errors, %d warnings\n", result.Errors, result.Warnings)
	} else {
		result.Status = "pass"
		logf(" clean\n")
	}

	// Write detail file if there are issues
	if len(issues) > 0 {
		detail := AnalyzeDetailFile{
			Path:   pkgPath,
			Issues: issues,
		}
		detailName := safePath(pkgPath) + ".json"
		detailPath := filepath.Join(session, "analyze", detailName)
		if err := writeJSONFile(detailPath, detail); err != nil {
			logf("  warning: failed to write detail file: %v\n", err)
		} else {
			result.DetailsFile = detailPath
		}
	}

	return result
}
