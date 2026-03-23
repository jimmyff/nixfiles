package cmd

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Test runs tests across discovered packages with compact JSON output.
func Test(args []string) int {
	fs := flag.NewFlagSet("test", flag.ExitOnError)
	path := fs.String("path", ".", "workspace root path")
	filter := fs.String("filter", "", "comma-separated package name filters")
	timeout := fs.Int("timeout", 120, "per-package timeout in seconds")
	cached := fs.Bool("cached", false, "read from cache instead of running live")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	// Cached mode: return cache file or empty output
	if *cached {
		data, err := readCache(root, "test.json")
		if err != nil {
			logf("error: %v\n", err)
			return ExitFailure
		}
		if data != nil {
			os.Stdout.Write(data)
			return ExitOK
		}
		out := TestOutput{Path: root, Packages: []TestPackageResult{}}
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
	logf("charm: found %d testable packages\n", len(testable))

	session, err := createSession()
	if err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	if err := ensureSessionSubdir(session, "test"); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	var results []TestPackageResult
	for _, pkg := range testable {
		runner := detectRunner(root, pkg.Path)
		result := runTestPackage(root, session, pkg.Path, runner, *timeout)
		results = append(results, result)
	}

	// Build summary
	summary := TestSummary{TotalPackages: len(results)}
	for _, r := range results {
		switch r.Status {
		case "pass":
			summary.PassedPackages++
		case "fail":
			summary.FailedPackages++
		case "error":
			summary.ErrorPackages++
		}
		summary.TotalTests += r.Total
		summary.TotalPassed += r.Passed
		summary.TotalFailed += r.Failed
		summary.TotalSkipped += r.Skipped
	}

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
	writeCache(root, "test.json", out)

	if summary.FailedPackages > 0 || summary.ErrorPackages > 0 {
		return ExitFailure
	}
	return ExitOK
}

func runTestPackage(root, session, pkgPath, runner string, timeout int) TestPackageResult {
	result := TestPackageResult{
		Path:   pkgPath,
		Runner: runner,
	}

	pkgDir := filepath.Join(root, pkgPath)

	// Create temp file for JSON report
	tmpFile, err := os.CreateTemp("", "charm-test-*.json")
	if err != nil {
		result.Status = "error"
		result.Error = fmt.Sprintf("failed to create temp file: %v", err)
		return result
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

	logf("  testing %s (%s)...", pkgPath, runner)
	start := time.Now()

	cmd := exec.Command(cmdName, cmdArgs...)
	cmd.Dir = pkgDir
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard

	// Use a timer goroutine for timeout instead of external timeout command
	done := make(chan error, 1)
	go func() {
		done <- cmd.Run()
	}()

	timer := time.NewTimer(time.Duration(timeout) * time.Second)
	defer timer.Stop()

	var runErr error
	select {
	case runErr = <-done:
		timer.Stop()
	case <-timer.C:
		// TODO: kill by process group (-pid) to avoid orphaned child processes on timeout
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		<-done // wait for goroutine
		runErr = fmt.Errorf("timeout after %ds", timeout)
	}

	elapsed := time.Since(start).Round(time.Millisecond)

	// Parse JSON report
	jsonData, readErr := os.ReadFile(jsonPath)
	if readErr != nil || len(jsonData) == 0 {
		if runErr != nil {
			result.Status = "error"
			result.Error = fmt.Sprintf("test command failed: %v", runErr)
		} else {
			result.Status = "error"
			result.Error = "no test output produced"
		}
		logf(" error (%s)\n", elapsed)
		return result
	}

	parsed := parseNDJSON(jsonData)
	result.Total = parsed.total
	result.Passed = parsed.passed
	result.Failed = parsed.failed
	result.Skipped = parsed.skipped

	if parsed.success && result.Failed == 0 {
		result.Status = "pass"
		logf(" %d passed (%s)\n", result.Passed, elapsed)
	} else {
		result.Status = "fail"
		logf(" %d failed (%s)\n", result.Failed, elapsed)
	}

	// Write detail file if there are failures
	if len(parsed.failures) > 0 {
		detail := TestDetailFile{
			Path:     pkgPath,
			Runner:   runner,
			Total:    result.Total,
			Passed:   result.Passed,
			Failed:   result.Failed,
			Skipped:  result.Skipped,
			Failures: parsed.failures,
		}
		detailName := safePath(pkgPath) + ".json"
		detailPath := filepath.Join(session, "test", detailName)
		if err := writeJSONFile(detailPath, detail); err != nil {
			logf("  warning: failed to write detail file: %v\n", err)
		} else {
			result.DetailsFile = detailPath
		}
	}

	return result
}

type parseOutput struct {
	total    int
	passed   int
	failed   int
	skipped  int
	success  bool
	failures []TestFailure
}

func parseNDJSON(data []byte) parseOutput {
	out := parseOutput{success: true}

	suites := map[int]string{}
	tests := map[int]string{}
	testSuite := map[int]int{}
	testLine := map[int]int{}
	errors := map[int][]ndjsonErrorEvent{}

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
				out.success = e.Success
			}
		}
	}
	return out
}
