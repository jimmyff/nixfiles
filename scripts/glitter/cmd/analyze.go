package cmd

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
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
	jobs := fs.Int("jobs", 4, "number of parallel analyze jobs")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Cached mode: assemble from per-package cache files
	if *cached {
		entries, err := readCacheTree(root, "analyze.json")
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		var results []AnalyzePackageResult
		var oldestTimestamp *string
		for relPath, data := range entries {
			var result AnalyzePackageResult
			if err := json.Unmarshal(data, &result); err != nil {
				continue
			}
			result.Path = relPath
			if result.Timestamp != nil && (oldestTimestamp == nil || *result.Timestamp < *oldestTimestamp) {
				oldestTimestamp = result.Timestamp
			}
			results = append(results, result)
		}
		sort.Slice(results, func(i, j int) bool {
			return results[i].Path < results[j].Path
		})
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
			Path:      root,
			Timestamp: oldestTimestamp,
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
		return ExitOK
	}

	filters := parseFilter(*filter)
	packages, err := discoverPackages(root, filters)
	if err != nil {
		logf("error: discovery failed: %v\n", err)
		return ExitFailure
	}

	logf("glittering: analyzing %d packages\n", len(packages))

	session, err := createSession()
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if err := ensureSessionSubdir(session, "analyze"); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	numJobs := *jobs
	if numJobs < 1 {
		numJobs = 1
	}

	type indexedResult struct {
		index  int
		result AnalyzePackageResult
	}
	resultsCh := make(chan indexedResult, len(packages))
	sem := make(chan struct{}, numJobs)
	var mu sync.Mutex

	for i, pkg := range packages {
		sem <- struct{}{}
		mu.Lock()
		logf("  analyzing %s...\n", pkg.Path)
		mu.Unlock()
		go func(i int, pkg PackageInfo) {
			result, logs := runAnalyzePackage(root, session, pkg.Path)
			result.Path = filepath.Join(root, pkg.Path)
			result.Timestamp = nowTimestamp()
			writeCache(filepath.Join(root, pkg.Path), "analyze.json", result)
			mu.Lock()
			fmt.Fprint(os.Stderr, logs)
			mu.Unlock()
			resultsCh <- indexedResult{index: i, result: result}
			<-sem
		}(i, pkg)
	}

	results := make([]AnalyzePackageResult, len(packages))
	for range packages {
		ir := <-resultsCh
		results[ir.index] = ir.result
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
		Path:      root,
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

	if summary.FailedPackages > 0 || summary.ErrorPackages > 0 {
		return ExitFailure
	}
	return ExitOK
}

func runAnalyzePackage(root, session, pkgPath string) (AnalyzePackageResult, string) {
	var buf strings.Builder
	result := AnalyzePackageResult{Path: pkgPath}
	pkgDir := filepath.Join(root, pkgPath)

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
		fmt.Fprintf(&buf, "  %s: error\n", pkgPath)
		return result, buf.String()
	}

	if result.Errors > 0 || result.Warnings > 0 {
		result.Status = "fail"
		fmt.Fprintf(&buf, "  %s: %d errors, %d warnings\n", pkgPath, result.Errors, result.Warnings)
	} else {
		result.Status = "pass"
		fmt.Fprintf(&buf, "  %s: clean\n", pkgPath)
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
			fmt.Fprintf(&buf, "  %s: warning: failed to write detail file: %v\n", pkgPath, err)
		} else {
			result.DetailsFile = detailPath
		}
	}

	return result, buf.String()
}
