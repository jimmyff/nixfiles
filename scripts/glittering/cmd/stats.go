package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	flag "github.com/spf13/pflag"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

// isGeneratedDart returns true for Dart codegen output files.
func isGeneratedDart(name string) bool {
	return strings.HasSuffix(name, ".g.dart") ||
		strings.HasSuffix(name, ".freezed.dart") ||
		strings.HasSuffix(name, ".gen.dart")
}

// countLines counts the number of lines in a file.
func countLines(path string) (int, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	count := 0
	for scanner.Scan() {
		count++
	}
	return count, scanner.Err()
}

// walkDartFiles walks a subdirectory within a package, counting .dart files
// and lines. Skips generated files and directories in skipDirs. Returns
// file count, line count, and any files exceeding the threshold.
func walkDartFiles(pkgDir, subdir string, threshold int) (int, int, []StatsOversizedFile) {
	dir := filepath.Join(pkgDir, subdir)
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return 0, 0, nil
	}

	var files, lines int
	var oversized []StatsOversizedFile

	filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			name := info.Name()
			if strings.HasPrefix(name, ".") || skipDirs[name] {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(info.Name(), ".dart") || isGeneratedDart(info.Name()) {
			return nil
		}
		n, err := countLines(path)
		if err != nil {
			return nil
		}
		files++
		lines += n
		if n >= threshold {
			rel, _ := filepath.Rel(pkgDir, path)
			oversized = append(oversized, StatsOversizedFile{File: rel, Lines: n})
		}
		return nil
	})

	return files, lines, oversized
}

// Stats counts files and lines per package and detects oversized files.
func Stats(args []string) int {
	fs := flag.NewFlagSet("stats", flag.ExitOnError)
	path := fs.String("path", ".", "workspace root path")
	filter := fs.String("filter", "", "comma-separated package name filters")
	cached := fs.Bool("cached", false, "read from cache instead of running live")
	jobs := fs.Int("jobs", 4, "number of parallel jobs")
	threshold := fs.Int("threshold", 200, "line count threshold for oversized files")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Cached mode
	if *cached {
		entries, err := readCacheTree(root, "stats.json")
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		var results []StatsPackageResult
		var oldestTimestamp *string
		for relPath, data := range entries {
			var result StatsPackageResult
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
		summary := buildStatsSummary(results)
		out := StatsOutput{
			Path:      root,
			Timestamp: oldestTimestamp,
			Threshold: *threshold,
			Packages:  results,
			Summary:   summary,
		}
		if out.Packages == nil {
			out.Packages = []StatsPackageResult{}
		}
		if err := outputJSON(out); err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		return ExitOK
	}

	// Live mode
	filters := parseFilter(*filter)
	packages, err := discoverPackages(root, filters)
	if err != nil {
		logf("error: discovery failed: %v\n", err)
		return ExitFailure
	}

	progressf("glittering: counting stats for %d packages\n", len(packages))

	session, err := createSession()
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if err := ensureSessionSubdir(session, "stats"); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	numJobs := *jobs
	if numJobs < 1 {
		numJobs = 1
	}

	type indexedResult struct {
		index  int
		result StatsPackageResult
	}
	resultsCh := make(chan indexedResult, len(packages))
	sem := make(chan struct{}, numJobs)
	var mu sync.Mutex

	for i, pkg := range packages {
		sem <- struct{}{}
		mu.Lock()
		progressf("  counting %s...\n", pkg.Path)
		mu.Unlock()
		go func(i int, pkg PackageInfo) {
			result, logs := runStatsPackage(root, session, pkg.Path, *threshold)
			result.Path = filepath.Join(root, pkg.Path)
			result.Timestamp = nowTimestamp()
			writeCache(filepath.Join(root, pkg.Path), "stats.json", result)
			mu.Lock()
			progressPrint(logs)
			mu.Unlock()
			resultsCh <- indexedResult{index: i, result: result}
			<-sem
		}(i, pkg)
	}

	results := make([]StatsPackageResult, len(packages))
	for range packages {
		ir := <-resultsCh
		results[ir.index] = ir.result
	}

	summary := buildStatsSummary(results)
	out := StatsOutput{
		Path:      root,
		Timestamp: nowTimestamp(),
		Session:   session,
		Threshold: *threshold,
		Packages:  results,
		Summary:   summary,
	}
	if out.Packages == nil {
		out.Packages = []StatsPackageResult{}
	}
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	return ExitOK
}

func runStatsPackage(root, session, pkgPath string, threshold int) (StatsPackageResult, string) {
	var buf strings.Builder
	result := StatsPackageResult{Path: pkgPath}
	pkgDir := filepath.Join(root, pkgPath)

	// Count source files (lib + bin)
	libFiles, libLines, libOversized := walkDartFiles(pkgDir, "lib", threshold)
	binFiles, binLines, binOversized := walkDartFiles(pkgDir, "bin", threshold)
	result.SourceFiles = libFiles + binFiles
	result.SourceLines = libLines + binLines

	// Count test files
	testFiles, testLines, testOversized := walkDartFiles(pkgDir, "test", threshold)
	result.TestFiles = testFiles
	result.TestLines = testLines

	// Combine oversized from all dirs
	var allOversized []StatsOversizedFile
	allOversized = append(allOversized, libOversized...)
	allOversized = append(allOversized, binOversized...)
	allOversized = append(allOversized, testOversized...)
	result.OversizedCount = len(allOversized)

	fmt.Fprintf(&buf, "  %s: %d files, %d lines", pkgPath, result.SourceFiles+result.TestFiles, result.SourceLines+result.TestLines)
	if result.OversizedCount > 0 {
		fmt.Fprintf(&buf, ", %d oversized", result.OversizedCount)
	}
	fmt.Fprintln(&buf)

	// Write detail file if oversized files found
	if len(allOversized) > 0 {
		detail := StatsDetailFile{
			Path:      pkgPath,
			Threshold: threshold,
			Oversized: allOversized,
		}
		detailName := safePath(pkgPath) + ".json"
		detailPath := filepath.Join(session, "stats", detailName)
		if err := writeJSONFile(detailPath, detail); err != nil {
			fmt.Fprintf(&buf, "  %s: warning: failed to write detail file: %v\n", pkgPath, err)
		} else {
			result.DetailsFile = detailPath
		}
	}

	return result, buf.String()
}

func buildStatsSummary(results []StatsPackageResult) StatsSummary {
	s := StatsSummary{TotalPackages: len(results)}
	for _, r := range results {
		s.TotalSourceFiles += r.SourceFiles
		s.TotalSourceLines += r.SourceLines
		s.TotalTestFiles += r.TestFiles
		s.TotalTestLines += r.TestLines
		s.TotalOversized += r.OversizedCount
	}
	return s
}
