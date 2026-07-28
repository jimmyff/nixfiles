//go:build darwin || linux

package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// --- runTestPackage subprocess tests (fake runner via PATH shim) ---

// A fake `dart` that writes a partial NDJSON report (one finished test, one
// started-but-never-finished), records a background grandchild's pid, then
// hangs — the shape of a real hung suite.
const hangingShim = `#!/bin/sh
for a in "$@"; do
  case "$a" in json:*) REPORT="${a#json:}" ;; esac
done
cat > "$REPORT" <<'EOF'
{"type":"suite","suite":{"id":0,"path":"test/hang_test.dart"}}
{"type":"testStart","test":{"id":1,"name":"passes","suiteID":0,"line":5,"column":3,"url":""}}
{"type":"testDone","testID":1,"result":"success","skipped":false,"hidden":false}
{"type":"testStart","test":{"id":2,"name":"hangs forever","suiteID":0,"line":9,"column":3,"url":""}}
EOF
sleep 300 &
echo $! > "$GLITTERING_TEST_GRANDCHILD_PID"
sleep 300
`

// A fake `dart` for an ordinary failing suite: complete report, non-zero exit.
const failingShim = `#!/bin/sh
for a in "$@"; do
  case "$a" in json:*) REPORT="${a#json:}" ;; esac
done
cat > "$REPORT" <<'EOF'
{"type":"suite","suite":{"id":0,"path":"test/fail_test.dart"}}
{"type":"testStart","test":{"id":1,"name":"fails","suiteID":0,"line":5,"column":3,"url":""}}
{"type":"error","testID":1,"error":"Expected: 2\n  Actual: 3","stackTrace":"test/fail_test.dart 7:5"}
{"type":"testDone","testID":1,"result":"failure","skipped":false,"hidden":false}
{"type":"done","success":false}
EOF
exit 1
`

// installShim writes an executable fake `dart` into a fresh dir and prepends
// it to PATH for the test.
func installShim(t *testing.T, script string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "dart"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// setupTestPkg creates a workspace root with one package dir and a session
// dir with the test/ subdir runTestPackage writes detail files into.
func setupTestPkg(t *testing.T) (root, session string) {
	t.Helper()
	root = t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "pkg"), 0o755); err != nil {
		t.Fatal(err)
	}
	session = t.TempDir()
	if err := os.MkdirAll(filepath.Join(session, "test"), 0o755); err != nil {
		t.Fatal(err)
	}
	return root, session
}

func TestRunTestPackage_TimeoutStatusAndDetail(t *testing.T) {
	installShim(t, hangingShim)
	root, session := setupTestPkg(t)
	t.Setenv("GLITTERING_TEST_GRANDCHILD_PID", filepath.Join(t.TempDir(), "grandchild.pid"))

	start := time.Now()
	result, logs := runTestPackage(root, session, "pkg", "dart", 1)
	elapsed := time.Since(start)

	if elapsed > 8*time.Second {
		t.Errorf("runTestPackage took %v — the kill must return promptly, not wait on the hung tree", elapsed)
	}
	if result.Status != "timeout" {
		t.Fatalf("status = %q (error: %q), want timeout", result.Status, result.Error)
	}
	if result.Total != 1 || result.Passed != 1 || result.Failed != 0 {
		t.Errorf("partial counts wrong: total=%d passed=%d failed=%d", result.Total, result.Passed, result.Failed)
	}
	for _, want := range []string{"timeout after 1s", "never finished", "test/hang_test.dart"} {
		if !strings.Contains(result.Error, want) {
			t.Errorf("result.Error %q missing %q", result.Error, want)
		}
	}
	if !strings.Contains(logs, "TIMEOUT") {
		t.Errorf("verbose log %q should mention the timeout", logs)
	}
	if result.DetailsFile == "" {
		t.Fatal("expected a details file naming the hung test")
	}
	data, err := os.ReadFile(result.DetailsFile)
	if err != nil {
		t.Fatalf("reading details file: %v", err)
	}
	var detail TestDetailFile
	if err := json.Unmarshal(data, &detail); err != nil {
		t.Fatalf("parsing details file: %v", err)
	}
	if len(detail.Incomplete) != 1 {
		t.Fatalf("expected 1 incomplete entry, got %d", len(detail.Incomplete))
	}
	if detail.Incomplete[0].TestName != "hangs forever" || detail.Incomplete[0].TestFile != "test/hang_test.dart" {
		t.Errorf("incomplete attribution wrong: %+v", detail.Incomplete[0])
	}
}

func TestRunTestPackage_TimeoutKillsGrandchildren(t *testing.T) {
	installShim(t, hangingShim)
	root, session := setupTestPkg(t)
	pidFile := filepath.Join(t.TempDir(), "grandchild.pid")
	t.Setenv("GLITTERING_TEST_GRANDCHILD_PID", pidFile)

	result, _ := runTestPackage(root, session, "pkg", "dart", 1)
	if result.Status != "timeout" {
		t.Fatalf("status = %q, want timeout", result.Status)
	}

	pidData, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatalf("grandchild pid not recorded: %v", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(pidData)))
	if err != nil {
		t.Fatalf("bad pid %q: %v", pidData, err)
	}

	deadline := time.Now().Add(3 * time.Second)
	for syscall.Kill(pid, 0) != syscall.ESRCH {
		if time.Now().After(deadline) {
			syscall.Kill(pid, syscall.SIGKILL) // don't leak it beyond the test
			t.Fatalf("grandchild %d still alive — process-group kill did not reach it", pid)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func TestRunTestPackage_FailingSuiteIsFailNotError(t *testing.T) {
	installShim(t, failingShim)
	root, session := setupTestPkg(t)

	result, _ := runTestPackage(root, session, "pkg", "dart", 30)
	if result.Status != "fail" {
		t.Fatalf("status = %q (error: %q), want fail — non-zero exit with a complete report is an ordinary failure", result.Status, result.Error)
	}
	if result.Total != 1 || result.Failed != 1 {
		t.Errorf("counts wrong: total=%d failed=%d", result.Total, result.Failed)
	}
	if result.DetailsFile == "" {
		t.Fatal("expected a details file for the failure")
	}
	var detail TestDetailFile
	data, err := os.ReadFile(result.DetailsFile)
	if err != nil {
		t.Fatalf("reading details file: %v", err)
	}
	if err := json.Unmarshal(data, &detail); err != nil {
		t.Fatalf("parsing details file: %v", err)
	}
	if len(detail.Failures) != 1 || detail.Failures[0].TestName != "fails" {
		t.Errorf("failure detail wrong: %+v", detail.Failures)
	}
	if len(detail.Incomplete) != 0 {
		t.Errorf("complete run must have no incomplete entries, got %+v", detail.Incomplete)
	}
}
