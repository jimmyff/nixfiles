package cmd

// --- Exit codes ---

const (
	ExitOK      = 0
	ExitFailure = 1
	ExitUsage   = 2
)

// --- Skip directories for package discovery ---

var skipDirs = map[string]bool{
	"build":        true,
	".dart_tool":   true,
	".symlinks":    true,
	"concepts":     true,
	"example":      true,
	"node_modules": true,
	"native":       true,
}

// --- Status command ---

type PackageInfo struct {
	Path            string `json:"path"`
	Name            string `json:"name"`
	Type            string `json:"type"` // "dart" or "flutter"
	HasTests        bool   `json:"has_tests"`
	Dependencies    int    `json:"dependencies"`
	DevDependencies int    `json:"dev_dependencies"`
}

type StatusOutput struct {
	Path     string        `json:"path"`
	Packages []PackageInfo `json:"packages"`
}

// --- Test command ---

type TestFailure struct {
	TestName   string `json:"test_name"`
	TestFile   string `json:"test_file"`
	Line       int    `json:"line,omitempty"`
	Error      string `json:"error"`
	StackTrace string `json:"stack_trace,omitempty"`
}

type TestPackageResult struct {
	Path        string  `json:"path"`
	Runner      string  `json:"runner"`
	Total       int     `json:"total"`
	Passed      int     `json:"passed"`
	Failed      int     `json:"failed"`
	Skipped     int     `json:"skipped"`
	Status      string  `json:"status"` // "pass", "fail", "error"
	Error       string  `json:"error,omitempty"`
	DetailsFile string  `json:"details_file,omitempty"`
	Timestamp   *string `json:"timestamp,omitempty"`
}

type TestDetailFile struct {
	Path     string        `json:"path"`
	Runner   string        `json:"runner"`
	Total    int           `json:"total"`
	Passed   int           `json:"passed"`
	Failed   int           `json:"failed"`
	Skipped  int           `json:"skipped"`
	Failures []TestFailure `json:"failures"`
}

type TestSummary struct {
	TotalPackages  int `json:"total_packages"`
	PassedPackages int `json:"passed_packages"`
	FailedPackages int `json:"failed_packages"`
	ErrorPackages  int `json:"error_packages"`
	TotalTests     int `json:"total_tests"`
	TotalPassed    int `json:"total_passed"`
	TotalFailed    int `json:"total_failed"`
	TotalSkipped   int `json:"total_skipped"`
}

type TestOutput struct {
	Path      string              `json:"path"`
	Timestamp *string             `json:"timestamp"`
	Session   string              `json:"session"`
	Packages  []TestPackageResult `json:"packages"`
	Summary   TestSummary         `json:"summary"`
}

// --- Analyze command ---

type AnalyzeIssue struct {
	Severity string `json:"severity"` // "info", "warning", "error"
	Message  string `json:"message"`
	File     string `json:"file"`
	Line     int    `json:"line"`
	Column   int    `json:"column"`
	Code     string `json:"code"`
}

type AnalyzePackageResult struct {
	Path        string  `json:"path"`
	Status      string  `json:"status"` // "pass", "fail", "error"
	Errors      int     `json:"errors"`
	Warnings    int     `json:"warnings"`
	Infos       int     `json:"infos"`
	Error       string  `json:"error,omitempty"`
	DetailsFile string  `json:"details_file,omitempty"`
	Timestamp   *string `json:"timestamp,omitempty"`
}

type AnalyzeDetailFile struct {
	Path   string         `json:"path"`
	Issues []AnalyzeIssue `json:"issues"`
}

type AnalyzeSummary struct {
	TotalPackages  int `json:"total_packages"`
	PassedPackages int `json:"passed_packages"`
	FailedPackages int `json:"failed_packages"`
	ErrorPackages  int `json:"error_packages"`
	TotalErrors    int `json:"total_errors"`
	TotalWarnings  int `json:"total_warnings"`
	TotalInfos     int `json:"total_infos"`
}

type AnalyzeOutput struct {
	Path      string                 `json:"path"`
	Timestamp *string                `json:"timestamp"`
	Session   string                 `json:"session"`
	Packages  []AnalyzePackageResult `json:"packages"`
	Summary   AnalyzeSummary         `json:"summary"`
}

// --- Get/Upgrade command ---

type PubPackageResult struct {
	Path   string `json:"path"`
	Runner string `json:"runner"`
	Status string `json:"status"` // "pass", "error"
	Error  string `json:"error,omitempty"`
}

type PubOutput struct {
	Path     string             `json:"path"`
	Packages []PubPackageResult `json:"packages"`
}

// --- Git command ---

type GitRepoStatus struct {
	Path           string   `json:"path"`
	Branch         string   `json:"branch"`
	Ref            string   `json:"ref"`
	Dirty          bool     `json:"dirty"`
	Ahead          int      `json:"ahead"`
	Behind         int      `json:"behind"`
	Upstream       string   `json:"upstream"`
	HeadOnRemote   bool     `json:"head_on_remote"`
	StashCount     int      `json:"stash_count"`
	UntrackedFiles []string `json:"untracked_files,omitempty"`
}

type GitSubmoduleStatus struct {
	Path           string `json:"path"`
	Branch         string `json:"branch"`
	Ref            string `json:"ref"`
	ParentRef      string `json:"parent_ref"`
	Dirty          bool   `json:"dirty"`
	Detached       bool   `json:"detached"`
	AheadRemote    int    `json:"ahead_remote"`
	BehindRemote   int    `json:"behind_remote"`
	AheadParent    int    `json:"ahead_parent"`
	BehindParent   int    `json:"behind_parent"`
	Upstream       string `json:"upstream"`
	HeadOnRemote   bool   `json:"head_on_remote"`
	StashCount     int    `json:"stash_count"`
	UntrackedCount int    `json:"untracked_count"`
	LatestCommit   string `json:"latest_commit"`
}

type GitOutput struct {
	Path       string               `json:"path"`
	Timestamp  *string              `json:"timestamp"`
	Repo       GitRepoStatus        `json:"repo"`
	Submodules []GitSubmoduleStatus `json:"submodules"`
}

// --- Git mutation outputs ---

type GitCommitResult struct {
	Path    string   `json:"path"`
	Success bool     `json:"success"`
	Ref     string   `json:"ref,omitempty"`
	Pushed  bool     `json:"pushed"`
	Staged  []string `json:"staged,omitempty"`
	Error   string   `json:"error,omitempty"`
}

type GitPullSubmodule struct {
	Path       string `json:"path"`
	Branch     string `json:"branch"`
	NewCommits int    `json:"new_commits"`
	WasDirty   bool   `json:"was_dirty,omitempty"`
	Error      string `json:"error,omitempty"`
}

type GitPullResult struct {
	Path       string             `json:"path"`
	Success    bool               `json:"success"`
	Branch     string             `json:"branch"`
	Submodules []GitPullSubmodule `json:"submodules"`
	Warnings   []string           `json:"warnings,omitempty"`
	Error      string             `json:"error,omitempty"`
}

// --- Git diff command ---

type DiffChangedFile struct {
	Path       string `json:"path"`
	Status     string `json:"status"` // M, A, D, R
	Insertions int    `json:"insertions"`
	Deletions  int    `json:"deletions"`
}

type DiffRepoResult struct {
	Path            string            `json:"path"`
	Branch          string            `json:"branch"`
	Staged          []DiffChangedFile `json:"staged"`
	Unstaged        []DiffChangedFile `json:"unstaged"`
	UntrackedFiles  []string          `json:"untracked_files"`
	TotalFiles      int               `json:"total_files"`
	TotalInsertions int               `json:"total_insertions"`
	TotalDeletions  int               `json:"total_deletions"`
	DetailsFile     string            `json:"details_file,omitempty"`
}

type DiffSummary struct {
	DirtyRepos      int `json:"dirty_repos"`
	TotalFiles      int `json:"total_files"`
	TotalInsertions int `json:"total_insertions"`
	TotalDeletions  int `json:"total_deletions"`
	TotalUntracked  int `json:"total_untracked"`
}

type DiffOutput struct {
	Path    string           `json:"path"`
	Session string           `json:"session"`
	Repos   []DiffRepoResult `json:"repos"`
	Summary DiffSummary      `json:"summary"`
}

// --- NDJSON event types (for dart test parsing) ---

type ndjsonGenericEvent struct {
	Type string `json:"type"`
}

type ndjsonSuiteEvent struct {
	Suite struct {
		ID   int    `json:"id"`
		Path string `json:"path"`
	} `json:"suite"`
}

type ndjsonTestStartEvent struct {
	Test struct {
		ID      int    `json:"id"`
		Name    string `json:"name"`
		SuiteID int    `json:"suiteID"`
		Line    int    `json:"line"`
		Column  int    `json:"column"`
		URL     string `json:"url"`
	} `json:"test"`
}

type ndjsonTestDoneEvent struct {
	TestID  int    `json:"testID"`
	Result  string `json:"result"`
	Skipped bool   `json:"skipped"`
	Hidden  bool   `json:"hidden"`
}

type ndjsonErrorEvent struct {
	TestID     int    `json:"testID"`
	Error      string `json:"error"`
	StackTrace string `json:"stackTrace"`
	IsFailure  bool   `json:"isFailure"`
}

type ndjsonDoneEvent struct {
	Success bool `json:"success"`
}
