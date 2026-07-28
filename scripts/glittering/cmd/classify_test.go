package cmd

import (
	"errors"
	"strings"
	"testing"
)

// --- classifyTestRun tests ---

func TestClassify_TimeoutWithPartialReport(t *testing.T) {
	parsed := parseOutput{
		total: 250, passed: 250,
		incomplete: []TestFailure{{TestName: "hang", TestFile: "test/location_globe_test.dart"}},
	}
	status, msg := classifyTestRun(parsed, true, true, errors.New("signal: killed"), 120)
	if status != "timeout" {
		t.Fatalf("status = %q, want timeout", status)
	}
	for _, want := range []string{"timeout after 120s", "250 passed", "1 started but never finished", "test/location_globe_test.dart"} {
		if !strings.Contains(msg, want) {
			t.Errorf("message %q missing %q", msg, want)
		}
	}
}

func TestClassify_TimeoutNoReport(t *testing.T) {
	status, msg := classifyTestRun(parseOutput{}, false, true, errors.New("signal: killed"), 60)
	if status != "timeout" {
		t.Fatalf("status = %q, want timeout even without a report", status)
	}
	if !strings.Contains(msg, "timeout after 60s") || !strings.Contains(msg, "no test output produced") {
		t.Errorf("unexpected message %q", msg)
	}
}

func TestClassify_FailingSuiteExitErrorIsFail(t *testing.T) {
	// The runner exits non-zero on any failing suite — that must stay a
	// normal "fail", not an "error".
	parsed := parseOutput{total: 3, passed: 2, failed: 1, sawDone: true, success: false}
	status, msg := classifyTestRun(parsed, true, false, errors.New("exit status 1"), 120)
	if status != "fail" || msg != "" {
		t.Errorf("got status=%q msg=%q, want fail with empty message", status, msg)
	}
}

func TestClassify_IncompleteNoTimeoutIsError(t *testing.T) {
	// No done event and no timeout: crashed runner or a kill racing the
	// timer — must never pass.
	parsed := parseOutput{total: 5, passed: 5, incomplete: []TestFailure{{TestName: "x"}}}
	status, msg := classifyTestRun(parsed, true, false, nil, 120)
	if status != "error" {
		t.Fatalf("status = %q, want error", status)
	}
	if !strings.Contains(msg, "no terminal done event") || !strings.Contains(msg, "1 tests never finished") {
		t.Errorf("unexpected message %q", msg)
	}
}

func TestClassify_IncompleteWithRunErrMentionsIt(t *testing.T) {
	parsed := parseOutput{total: 1, passed: 1}
	status, msg := classifyTestRun(parsed, true, false, errors.New("signal: segmentation fault"), 120)
	if status != "error" {
		t.Fatalf("status = %q, want error", status)
	}
	if !strings.Contains(msg, "signal: segmentation fault") {
		t.Errorf("message %q should mention the command error", msg)
	}
}

func TestClassify_NoReportWithRunErr(t *testing.T) {
	status, msg := classifyTestRun(parseOutput{}, false, false, errors.New("exit status 64"), 120)
	if status != "error" || !strings.Contains(msg, "test command failed: exit status 64") {
		t.Errorf("got status=%q msg=%q", status, msg)
	}
}

func TestClassify_NoReportNoErr(t *testing.T) {
	status, msg := classifyTestRun(parseOutput{}, false, false, nil, 120)
	if status != "error" || msg != "no test output produced" {
		t.Errorf("got status=%q msg=%q", status, msg)
	}
}

func TestClassify_CompleteReportWithExitErrorStillPass(t *testing.T) {
	// A complete, clean report is authoritative over the exit code.
	parsed := parseOutput{total: 2, passed: 2, sawDone: true, success: true}
	status, _ := classifyTestRun(parsed, true, false, errors.New("exit status 1"), 120)
	if status != "pass" {
		t.Errorf("status = %q, want pass", status)
	}
}

func TestClassify_HappyPaths(t *testing.T) {
	pass := parseOutput{total: 2, passed: 2, sawDone: true, success: true}
	if status, _ := classifyTestRun(pass, true, false, nil, 120); status != "pass" {
		t.Errorf("clean run: status = %q, want pass", status)
	}
	// done reported success=false with no counted failures still fails
	doneFalse := parseOutput{total: 2, passed: 2, sawDone: true, success: false}
	if status, _ := classifyTestRun(doneFalse, true, false, nil, 120); status != "fail" {
		t.Errorf("done success=false: status = %q, want fail", status)
	}
}

// --- buildTestSummary tests ---

func TestBuildTestSummary_AllStatuses(t *testing.T) {
	results := []TestPackageResult{
		{Status: "pass", Total: 10, Passed: 10},
		{Status: "fail", Total: 5, Passed: 3, Failed: 2},
		{Status: "error"},
		{Status: "timeout", Total: 4, Passed: 4},
		{Status: "bogus"}, // unknown statuses must never render green
	}
	s := buildTestSummary(results)
	if s.TotalPackages != 5 || s.PassedPackages != 1 || s.FailedPackages != 1 || s.TimeoutPackages != 1 {
		t.Errorf("package buckets wrong: %+v", s)
	}
	if s.ErrorPackages != 2 {
		t.Errorf("ErrorPackages = %d, want 2 (error + unknown status)", s.ErrorPackages)
	}
	if s.TotalTests != 19 || s.TotalPassed != 17 || s.TotalFailed != 2 {
		t.Errorf("test totals wrong: %+v", s)
	}
}
