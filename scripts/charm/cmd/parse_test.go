package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// --- parseNDJSON tests ---

func TestParseNDJSON_Pass(t *testing.T) {
	data := []byte(`{"type":"suite","suite":{"id":0,"path":"test/foo_test.dart"}}
{"type":"testStart","test":{"id":1,"name":"adds two","suiteID":0,"line":5,"column":3,"url":""}}
{"type":"testDone","testID":1,"result":"success","skipped":false,"hidden":false}
{"type":"done","success":true}
`)
	out := parseNDJSON(data)
	if out.total != 1 || out.passed != 1 || out.failed != 0 || out.skipped != 0 {
		t.Errorf("expected 1 passed, got total=%d passed=%d failed=%d skipped=%d", out.total, out.passed, out.failed, out.skipped)
	}
	if !out.success {
		t.Error("expected success=true")
	}
}

func TestParseNDJSON_Fail(t *testing.T) {
	data := []byte(`{"type":"suite","suite":{"id":0,"path":"test/bar_test.dart"}}
{"type":"testStart","test":{"id":1,"name":"fails","suiteID":0,"line":10,"column":3,"url":""}}
{"type":"error","testID":1,"error":"Expected: 2\n  Actual: 3","stackTrace":"test/bar_test.dart 12:5","isFailure":true}
{"type":"testDone","testID":1,"result":"failure","skipped":false,"hidden":false}
{"type":"done","success":false}
`)
	out := parseNDJSON(data)
	if out.total != 1 || out.passed != 0 || out.failed != 1 {
		t.Errorf("expected 1 failed, got total=%d passed=%d failed=%d", out.total, out.passed, out.failed)
	}
	if out.success {
		t.Error("expected success=false")
	}
	if len(out.failures) != 1 {
		t.Fatalf("expected 1 failure, got %d", len(out.failures))
	}
	if out.failures[0].TestName != "fails" {
		t.Errorf("expected test name 'fails', got %q", out.failures[0].TestName)
	}
	if out.failures[0].TestFile != "test/bar_test.dart" {
		t.Errorf("expected test file 'test/bar_test.dart', got %q", out.failures[0].TestFile)
	}
}

func TestParseNDJSON_Skip(t *testing.T) {
	data := []byte(`{"type":"testStart","test":{"id":1,"name":"skipped test","suiteID":0,"line":1,"column":1,"url":""}}
{"type":"testDone","testID":1,"result":"success","skipped":true,"hidden":false}
{"type":"done","success":true}
`)
	out := parseNDJSON(data)
	if out.total != 1 || out.skipped != 1 || out.passed != 0 {
		t.Errorf("expected 1 skipped, got total=%d skipped=%d passed=%d", out.total, out.skipped, out.passed)
	}
}

func TestParseNDJSON_HiddenIgnored(t *testing.T) {
	data := []byte(`{"type":"testStart","test":{"id":1,"name":"hidden","suiteID":0,"line":1,"column":1,"url":""}}
{"type":"testDone","testID":1,"result":"success","skipped":false,"hidden":true}
{"type":"done","success":true}
`)
	out := parseNDJSON(data)
	if out.total != 0 {
		t.Errorf("expected 0 total (hidden tests ignored), got %d", out.total)
	}
}

func TestParseNDJSON_Empty(t *testing.T) {
	out := parseNDJSON([]byte(""))
	if out.total != 0 || out.passed != 0 || out.failed != 0 || out.skipped != 0 {
		t.Errorf("expected all zeros for empty input, got total=%d passed=%d failed=%d skipped=%d", out.total, out.passed, out.failed, out.skipped)
	}
	if !out.success {
		t.Error("expected success=true for empty input (default)")
	}
}

// --- analyzePattern tests ---

func TestAnalyzePattern_Match(t *testing.T) {
	lines := []struct {
		input    string
		severity string
		file     string
		line     string
		col      string
		message  string
		code     string
	}{
		{
			input:    "   info - lib/foo.dart:3:1 - Unused import: 'package:bar/bar.dart'. Try removing the import directive. - unused_import",
			severity: "info",
			file:     "lib/foo.dart",
			line:     "3",
			col:      "1",
			message:  "Unused import: 'package:bar/bar.dart'. Try removing the import directive.",
			code:     "unused_import",
		},
		{
			input:    "warning - lib/bar.dart:42:10 - Dead code. Try removing the code. - dead_code",
			severity: "warning",
			file:     "lib/bar.dart",
			line:     "42",
			col:      "10",
			message:  "Dead code. Try removing the code.",
			code:     "dead_code",
		},
		{
			input:    "   error - lib/baz.dart:100:5 - Undefined name 'foo'. Try correcting the name. - undefined_identifier",
			severity: "error",
			file:     "lib/baz.dart",
			line:     "100",
			col:      "5",
			message:  "Undefined name 'foo'. Try correcting the name.",
			code:     "undefined_identifier",
		},
	}
	for _, tc := range lines {
		matches := analyzePattern.FindStringSubmatch(tc.input)
		if matches == nil {
			t.Errorf("expected match for %q", tc.input)
			continue
		}
		if matches[1] != tc.severity {
			t.Errorf("severity: got %q, want %q", matches[1], tc.severity)
		}
		if matches[2] != tc.file {
			t.Errorf("file: got %q, want %q", matches[2], tc.file)
		}
		if matches[3] != tc.line {
			t.Errorf("line: got %q, want %q", matches[3], tc.line)
		}
		if matches[4] != tc.col {
			t.Errorf("col: got %q, want %q", matches[4], tc.col)
		}
		if matches[5] != tc.message {
			t.Errorf("message: got %q, want %q", matches[5], tc.message)
		}
		if matches[6] != tc.code {
			t.Errorf("code: got %q, want %q", matches[6], tc.code)
		}
	}
}

func TestAnalyzePattern_NoMatch(t *testing.T) {
	nonMatching := []string{
		"Analyzing project...",
		"  No issues found!",
		"3 issues found.",
		"",
	}
	for _, line := range nonMatching {
		if analyzePattern.FindStringSubmatch(line) != nil {
			t.Errorf("expected no match for %q", line)
		}
	}
}

// --- parsePubspec tests ---

func TestParsePubspec_Dart(t *testing.T) {
	dir := t.TempDir()
	pubspec := filepath.Join(dir, "pubspec.yaml")
	os.WriteFile(pubspec, []byte(`name: my_dart_pkg
dependencies:
  http: ^1.0.0
  path: ^1.8.0
dev_dependencies:
  test: ^1.24.0
`), 0644)

	pkg := parsePubspec(pubspec, "my_dart_pkg")
	if pkg.Name != "my_dart_pkg" {
		t.Errorf("name: got %q, want %q", pkg.Name, "my_dart_pkg")
	}
	if pkg.Type != "dart" {
		t.Errorf("type: got %q, want %q", pkg.Type, "dart")
	}
	if pkg.Dependencies != 2 {
		t.Errorf("dependencies: got %d, want 2", pkg.Dependencies)
	}
	if pkg.DevDependencies != 1 {
		t.Errorf("dev_dependencies: got %d, want 1", pkg.DevDependencies)
	}
}

func TestParsePubspec_FlutterViaDep(t *testing.T) {
	dir := t.TempDir()
	pubspec := filepath.Join(dir, "pubspec.yaml")
	os.WriteFile(pubspec, []byte(`name: my_flutter_app
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.0
dev_dependencies:
  flutter_test:
    sdk: flutter
`), 0644)

	pkg := parsePubspec(pubspec, "my_flutter_app")
	if pkg.Type != "flutter" {
		t.Errorf("type: got %q, want %q", pkg.Type, "flutter")
	}
	// 3 because "sdk: flutter" under flutter: is also counted as indented colon line
	if pkg.Dependencies != 3 {
		t.Errorf("dependencies: got %d, want 3", pkg.Dependencies)
	}
}

func TestParsePubspec_FlutterViaDevDep(t *testing.T) {
	dir := t.TempDir()
	pubspec := filepath.Join(dir, "pubspec.yaml")
	os.WriteFile(pubspec, []byte(`name: pure_dart_with_flutter_test
dependencies:
  http: ^1.0.0
dev_dependencies:
  flutter_test:
    sdk: flutter
`), 0644)

	pkg := parsePubspec(pubspec, "pure_dart_with_flutter_test")
	if pkg.Type != "flutter" {
		t.Errorf("type: got %q, want %q (flutter_test in dev_dependencies should detect flutter)", pkg.Type, "flutter")
	}
}

func TestParsePubspec_HasTests(t *testing.T) {
	dir := t.TempDir()
	pubspec := filepath.Join(dir, "pubspec.yaml")
	os.WriteFile(pubspec, []byte(`name: testable
`), 0644)
	os.Mkdir(filepath.Join(dir, "test"), 0755)

	pkg := parsePubspec(pubspec, "testable")
	if !pkg.HasTests {
		t.Error("expected has_tests=true when test/ directory exists")
	}
}
