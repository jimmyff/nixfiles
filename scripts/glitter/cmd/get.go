package cmd

import (
	flag "github.com/spf13/pflag"
	"path/filepath"
	"strings"
	"time"
)

// Get runs pub get across discovered packages.
func Get(args []string) int {
	return pubCommand(args, "get")
}

// Upgrade runs pub upgrade across discovered packages.
func Upgrade(args []string) int {
	return pubCommand(args, "upgrade")
}

func pubCommand(args []string, operation string) int {
	fs := flag.NewFlagSet(operation, flag.ExitOnError)
	path := fs.String("path", ".", "workspace root path")
	filter := fs.String("filter", "", "comma-separated package name filters")
	fs.BoolVarP(&verbose, "verbose", "v", false, "show progress logs")
	fs.Parse(args)

	root, err := resolveRoot(*path)
	if err != nil {
		logf("error: %v\n", err)
		return ExitUsage
	}

	filters := parseFilter(*filter)
	packages, err := discoverPackages(root, filters)
	if err != nil {
		logf("error: discovery failed: %v\n", err)
		return ExitFailure
	}

	progressf("glittering: running pub %s on %d packages\n", operation, len(packages))

	var results []PubPackageResult
	for _, pkg := range packages {
		result := runPubCommand(root, pkg.Path, pkg.Type, operation)
		results = append(results, result)
	}

	out := PubOutput{Path: root, Packages: results}
	if out.Packages == nil {
		out.Packages = []PubPackageResult{}
	}
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}

	return ExitOK
}

func runPubCommand(root, pkgPath, pkgType, operation string) PubPackageResult {
	result := PubPackageResult{
		Path:   pkgPath,
		Runner: pkgType,
	}

	pkgDir := filepath.Join(root, pkgPath)
	runner := pkgType
	if runner == "" {
		runner = detectRunner(root, pkgPath)
	}
	result.Runner = runner

	progressf("  %s pub %s (%s)...", pkgPath, operation, runner)

	_, stderr, err := runCommand(pkgDir, 120*time.Second, runner, "pub", operation)
	if err != nil {
		result.Status = "error"
		result.Error = strings.TrimSpace(stderr)
		progressf(" error\n")
	} else {
		result.Status = "pass"
		progressf(" ok\n")
	}

	return result
}
