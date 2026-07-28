package cmd

import (
	"encoding/json"
	"fmt"
	flag "github.com/spf13/pflag"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

// Test runs tests across discovered packages with compact JSON output.
func Test(args []string) int {
	fs := flag.NewFlagSet("test", flag.ExitOnError)
	path := fs.String("path", ".", "workspace root path")
	filter := fs.String("filter", "", "comma-separated package name filters")
	timeout := fs.Int("timeout", 120, "per-package timeout in seconds")
	cached := fs.Bool("cached", false, "read from cache instead of running live")
	jobs := fs.Int("jobs", 4, "number of parallel test jobs")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Cached mode: assemble from per-package cache files
	if *cached {
		entries, err := readCacheTree(root, "test.json")
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		var results []TestPackageResult
		var oldestTimestamp *string
		for relPath, data := range entries {
			var result TestPackageResult
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
		out := TestOutput{
			Path:      root,
			Timestamp: oldestTimestamp,
			Packages:  results,
			Summary:   buildTestSummary(results),
		}
		if out.Packages == nil {
			out.Packages = []TestPackageResult{}
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

	// Filter to packages with tests
	var testable []PackageInfo
	for _, pkg := range packages {
		if pkg.HasTests {
			testable = append(testable, pkg)
		}
	}
	progressf("glittering: found %d testable packages\n", len(testable))

	session, err := createSession()
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if err := ensureSessionSubdir(session, "test"); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	// Setpgid detaches test processes from the terminal's foreground group,
	// so Ctrl-C must be forwarded to them explicitly.
	installSignalHandler()

	numJobs := *jobs
	if numJobs < 1 {
		numJobs = 1
	}

	type indexedResult struct {
		index  int
		result TestPackageResult
	}
	resultsCh := make(chan indexedResult, len(testable))
	sem := make(chan struct{}, numJobs)
	var mu sync.Mutex

	for i, pkg := range testable {
		runner := pkg.Type
		sem <- struct{}{} // acquire slot before printing
		mu.Lock()
		progressf("  testing %s (%s)...\n", pkg.Path, runner)
		mu.Unlock()
		go func(i int, pkg PackageInfo, runner string) {
			result, logs := runTestPackage(root, session, pkg.Path, runner, *timeout)
			result.Path = pkg.Path // relative: worktree-portable cache, consistent with --cached
			result.Timestamp = nowTimestamp()
			writeCache(filepath.Join(root, pkg.Path), "test.json", result)
			mu.Lock()
			progressPrint(logs)
			mu.Unlock()
			resultsCh <- indexedResult{index: i, result: result}
			<-sem // release slot
		}(i, pkg, runner)
	}

	results := make([]TestPackageResult, len(testable))
	for range testable {
		ir := <-resultsCh
		results[ir.index] = ir.result
	}

	summary := buildTestSummary(results)

	out := TestOutput{
		Path:      root,
		Timestamp: nowTimestamp(),
		Session:   session,
		Packages:  results,
		Summary:   summary,
	}
	if out.Packages == nil {
		out.Packages = []TestPackageResult{}
	}
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	if summary.FailedPackages+summary.ErrorPackages+summary.TimeoutPackages > 0 {
		return ExitFailure
	}
	return ExitOK
}

func runTestPackage(root, session, pkgPath, runner string, timeout int) (TestPackageResult, string) {
	var buf strings.Builder
	result := TestPackageResult{
		Path:   pkgPath,
		Runner: runner,
	}

	pkgDir := filepath.Join(root, pkgPath)

	// Create temp file for JSON report
	tmpFile, err := os.CreateTemp("", "glittering-test-*.json")
	if err != nil {
		result.Status = "error"
		result.Error = fmt.Sprintf("failed to create temp file: %v", err)
		fmt.Fprintf(&buf, "  %s: error\n", pkgPath)
		return result, buf.String()
	}
	jsonPath := tmpFile.Name()
	tmpFile.Close()
	defer os.Remove(jsonPath)

	// Build command
	var cmdName string
	var cmdArgs []string

	// Check for test.sh on Linux (NixOS SQLite workaround)
	testSh := filepath.Join(pkgDir, "test.sh")
	useTestSh := false
	if runtime.GOOS == "linux" {
		if _, err := os.Stat(testSh); err == nil {
			useTestSh = true
		}
	}

	if useTestSh {
		cmdName = "bash"
		cmdArgs = []string{testSh, "--file-reporter", "json:" + jsonPath}
	} else {
		cmdName = runner
		cmdArgs = []string{"test", "--file-reporter", "json:" + jsonPath}
	}

	start := time.Now()

	cmd := exec.Command(cmdName, cmdArgs...)
	cmd.Dir = pkgDir
	// Stdout/Stderr stay nil so os/exec wires the child to /dev/null directly:
	// no pipes, no copy goroutines, so Wait returns as soon as the direct
	// child is reaped even if grandchildren survive.
	setProcGroup(cmd)

	if err := cmd.Start(); err != nil {
		result.Status = "error"
		result.Error = fmt.Sprintf("failed to start %s: %v", cmdName, err)
		fmt.Fprintf(&buf, "  %s: error\n", pkgPath)
		return result, buf.String()
	}
	unregister := registerProcGroup(cmd)
	defer unregister()

	done := make(chan error, 1)
	go func() {
		done <- cmd.Wait()
	}()

	timer := time.NewTimer(time.Duration(timeout) * time.Second)
	defer timer.Stop()

	var runErr error
	var timedOut bool
	select {
	case runErr = <-done:
	case <-timer.C:
		timedOut = true
		killProcGroup(cmd)
		select {
		case runErr = <-done:
		case <-time.After(5 * time.Second): // never hang glittering itself
		}
	}

	elapsed := time.Since(start).Round(time.Millisecond)

	// Parse JSON report; the reporter streams incrementally, so a killed run
	// leaves a partial (but parseable) file behind.
	jsonData, readErr := os.ReadFile(jsonPath)
	hasReport := readErr == nil && len(jsonData) > 0
	var parsed parseOutput
	if hasReport {
		parsed = parseNDJSON(jsonData)
	}

	result.Total = parsed.total
	result.Passed = parsed.passed
	result.Failed = parsed.failed
	result.Skipped = parsed.skipped
	result.Status, result.Error = classifyTestRun(parsed, hasReport, timedOut, runErr, timeout)

	switch result.Status {
	case "pass":
		fmt.Fprintf(&buf, "  %s: %d passed (%s)\n", pkgPath, result.Passed, elapsed)
	case "fail":
		fmt.Fprintf(&buf, "  %s: %d failed (%s)\n", pkgPath, result.Failed, elapsed)
	case "timeout":
		fmt.Fprintf(&buf, "  %s: TIMEOUT after %ds — %d passed, %d failed, %d never finished (%s)\n",
			pkgPath, timeout, result.Passed, result.Failed, len(parsed.incomplete), elapsed)
	default:
		fmt.Fprintf(&buf, "  %s: error (%s)\n", pkgPath, elapsed)
	}

	// Write detail file if there is anything to attribute
	if len(parsed.failures) > 0 || len(parsed.incomplete) > 0 {
		failures := parsed.failures
		if failures == nil {
			failures = []TestFailure{}
		}
		detail := TestDetailFile{
			Path:       pkgPath,
			Runner:     runner,
			Total:      result.Total,
			Passed:     result.Passed,
			Failed:     result.Failed,
			Skipped:    result.Skipped,
			Failures:   failures,
			Incomplete: parsed.incomplete,
		}
		detailName := safePath(pkgPath) + ".json"
		detailPath := filepath.Join(session, "test", detailName)
		if err := writeJSONFile(detailPath, detail); err != nil {
			fmt.Fprintf(&buf, "  %s: warning: failed to write detail file: %v\n", pkgPath, err)
		} else {
			result.DetailsFile = detailPath
		}
	}

	return result, buf.String()
}

// classifyTestRun maps a parsed report plus process outcome to a package
// status and error message. hasReport is false when the JSON report file was
// unreadable or empty. timedOut is set only when glittering killed the run at
// the per-package cap — runErr alone cannot distinguish that from an ordinary
// failing suite, since the runner exits non-zero on failures too.
func classifyTestRun(parsed parseOutput, hasReport, timedOut bool, runErr error, timeoutSecs int) (string, string) {
	switch {
	case timedOut:
		if !hasReport {
			return "timeout", fmt.Sprintf("timeout after %ds; no test output produced", timeoutSecs)
		}
		msg := fmt.Sprintf("timeout after %ds; %d passed, %d failed", timeoutSecs, parsed.passed, parsed.failed)
		if n := len(parsed.incomplete); n > 0 {
			msg += fmt.Sprintf(", %d started but never finished (first: %s: %s)",
				n, parsed.incomplete[0].TestFile, parsed.incomplete[0].TestName)
		}
		return "timeout", msg
	case !hasReport && runErr != nil:
		return "error", fmt.Sprintf("test command failed: %v", runErr)
	case !hasReport:
		return "error", "no test output produced"
	case !parsed.sawDone:
		// Stream never reached its terminal done event: crashed runner or a
		// kill that raced the timer — incomplete output must never pass.
		msg := fmt.Sprintf("test output incomplete (no terminal done event); %d tests never finished", len(parsed.incomplete))
		if runErr != nil {
			msg += fmt.Sprintf("; command error: %v", runErr)
		}
		return "error", msg
	case parsed.failed > 0 || !parsed.success:
		return "fail", ""
	default:
		// A complete report is authoritative — a non-zero exit with a clean
		// done event stays a pass.
		return "pass", ""
	}
}

// buildTestSummary aggregates package results. Unknown statuses count as
// errors so a future status can never silently render green.
func buildTestSummary(results []TestPackageResult) TestSummary {
	summary := TestSummary{TotalPackages: len(results)}
	for _, r := range results {
		switch r.Status {
		case "pass":
			summary.PassedPackages++
		case "fail":
			summary.FailedPackages++
		case "timeout":
			summary.TimeoutPackages++
		default:
			summary.ErrorPackages++
		}
		summary.TotalTests += r.Total
		summary.TotalPassed += r.Passed
		summary.TotalFailed += r.Failed
		summary.TotalSkipped += r.Skipped
	}
	return summary
}

type parseOutput struct {
	total      int
	passed     int
	failed     int
	skipped    int
	success    bool // from the terminal "done" event; meaningful only when sawDone
	sawDone    bool // terminal {"type":"done"} event was seen — absent when the run was killed
	failures   []TestFailure
	incomplete []TestFailure // started (testStart) but never finished (no testDone)
}

func parseNDJSON(data []byte) parseOutput {
	var out parseOutput

	suites := map[int]string{}
	tests := map[int]string{}
	testSuite := map[int]int{}
	testLine := map[int]int{}
	errors := map[int][]ndjsonErrorEvent{}
	doneIDs := map[int]bool{}

	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var ev ndjsonGenericEvent
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			continue
		}
		switch ev.Type {
		case "suite":
			var e ndjsonSuiteEvent
			if json.Unmarshal([]byte(line), &e) == nil {
				suites[e.Suite.ID] = e.Suite.Path
			}
		case "testStart":
			var e ndjsonTestStartEvent
			if json.Unmarshal([]byte(line), &e) == nil {
				tests[e.Test.ID] = e.Test.Name
				testSuite[e.Test.ID] = e.Test.SuiteID
				testLine[e.Test.ID] = e.Test.Line
			}
		case "testDone":
			var e ndjsonTestDoneEvent
			if json.Unmarshal([]byte(line), &e) == nil {
				doneIDs[e.TestID] = true // any testDone (hidden included) means finished
				if e.Hidden {
					continue
				}
				if e.Skipped {
					out.skipped++
					out.total++
					continue
				}
				out.total++
				if e.Result == "success" {
					out.passed++
				} else {
					out.failed++
					f := TestFailure{
						TestName: tests[e.TestID],
						TestFile: suites[testSuite[e.TestID]],
						Line:     testLine[e.TestID],
					}
					if errs, ok := errors[e.TestID]; ok && len(errs) > 0 {
						f.Error = errs[0].Error
						f.StackTrace = errs[0].StackTrace
					}
					out.failures = append(out.failures, f)
				}
			}
		case "error":
			var e ndjsonErrorEvent
			if json.Unmarshal([]byte(line), &e) == nil {
				errors[e.TestID] = append(errors[e.TestID], e)
			}
		case "done":
			var e ndjsonDoneEvent
			if json.Unmarshal([]byte(line), &e) == nil {
				out.sawDone = true
				out.success = e.Success
			}
		}
	}

	// Tests that started but never finished — not counted in the totals
	// (those stay truthful to testDone events) but surfaced so a hang or
	// killed run is attributable to its test and file.
	var unfinished []int
	for id := range tests {
		if !doneIDs[id] {
			unfinished = append(unfinished, id)
		}
	}
	sort.Ints(unfinished)
	for _, id := range unfinished {
		f := TestFailure{
			TestName: tests[id],
			TestFile: suites[testSuite[id]],
			Line:     testLine[id],
			Error:    "started but never finished",
		}
		if errs := errors[id]; len(errs) > 0 {
			f.Error = errs[0].Error
			f.StackTrace = errs[0].StackTrace
		}
		out.incomplete = append(out.incomplete, f)
	}
	return out
}
