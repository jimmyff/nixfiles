package cmd

import "testing"

func TestParseLeftRight_Valid(t *testing.T) {
	left, right := parseLeftRight("3\t5")
	if left != 3 || right != 5 {
		t.Errorf("expected (3, 5), got (%d, %d)", left, right)
	}
}

func TestParseLeftRight_Zeros(t *testing.T) {
	left, right := parseLeftRight("0\t0")
	if left != 0 || right != 0 {
		t.Errorf("expected (0, 0), got (%d, %d)", left, right)
	}
}

func TestParseLeftRight_Empty(t *testing.T) {
	left, right := parseLeftRight("")
	if left != 0 || right != 0 {
		t.Errorf("expected (0, 0) for empty input, got (%d, %d)", left, right)
	}
}

func TestParseLeftRight_NonNumeric(t *testing.T) {
	left, right := parseLeftRight("abc\tdef")
	if left != 0 || right != 0 {
		t.Errorf("expected (0, 0) for non-numeric, got (%d, %d)", left, right)
	}
}

func TestParseLeftRight_WrongFieldCount(t *testing.T) {
	left, right := parseLeftRight("1")
	if left != 0 || right != 0 {
		t.Errorf("expected (0, 0) for single field, got (%d, %d)", left, right)
	}

	left, right = parseLeftRight("1\t2\t3")
	if left != 0 || right != 0 {
		t.Errorf("expected (0, 0) for three fields, got (%d, %d)", left, right)
	}
}

func TestCountUntracked(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected int
	}{
		{"empty", "", 0},
		{"no untracked", " M file.go\nA  new.go", 0},
		{"one untracked", "?? foo.txt", 1},
		{"mixed", " M file.go\n?? bar.txt\n?? baz.txt", 2},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := countUntracked(tc.input)
			if got != tc.expected {
				t.Errorf("countUntracked(%q) = %d, want %d", tc.input, got, tc.expected)
			}
		})
	}
}
