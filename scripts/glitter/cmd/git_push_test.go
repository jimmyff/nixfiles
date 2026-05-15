package cmd

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Regression: --filter scopes pushes to submodules, so a dirty parent should
// not block the operation. Pre-flight used to abort with "parent repo has
// uncommitted changes" even when the parent wasn't being pushed.
func TestGitPush_FilterIgnoresParentDirty(t *testing.T) {
	tmp := t.TempDir()
	for _, args := range [][]string{
		{"init", "--quiet", "--initial-branch=main"},
		{"config", "user.email", "test@example.com"},
		{"config", "user.name", "test"},
		{"commit", "--quiet", "--allow-empty", "-m", "init"},
	} {
		cmd := exec.Command("git", args...)
		cmd.Dir = tmp
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v failed: %v: %s", args, err, out)
		}
	}
	if err := os.WriteFile(filepath.Join(tmp, "dirt.txt"), []byte("untracked"), 0644); err != nil {
		t.Fatalf("write dirt: %v", err)
	}

	var got int
	stdout := captureStdout(t, func() {
		got = GitPush([]string{"--path", tmp, "--filter", "nonexistent-sub"})
	})

	var output PushOutput
	if err := json.Unmarshal([]byte(stdout), &output); err != nil {
		t.Fatalf("output is not valid JSON: %v\noutput: %s", err, stdout)
	}
	if strings.Contains(output.Error, "parent repo has uncommitted changes") {
		t.Errorf("filter set but parent-dirty preflight still fired: %q", output.Error)
	}
	if got != ExitOK {
		t.Errorf("expected ExitOK with no submodules to push, got %d (error: %q)", got, output.Error)
	}
}
