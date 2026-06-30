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

	// Parallel across packages (pub locks the shared cache, so concurrent gets are
	// safe); indexed results preserve discovery order.
	const maxJobs = 8
	type indexed struct {
		i int
		r PubPackageResult
	}
	ch := make(chan indexed, len(packages))
	sem := make(chan struct{}, maxJobs)
	for i, pkg := range packages {
		sem <- struct{}{}
		go func(i int, pkg PackageInfo) {
			defer func() { <-sem }()
			ch <- indexed{i, runPubCommand(root, pkg.Path, pkg.Type, operation)}
		}(i, pkg)
	}
	results := make([]PubPackageResult, len(packages))
	for range packages {
		r := <-ch
		results[r.i] = r.r
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

	_, stderr, err := runCommand(pkgDir, 120*time.Second, pkgType, "pub", operation)
	if err != nil {
		result.Status = "error"
		result.Error = strings.TrimSpace(stderr)
		progressf("  %s pub %s (%s): error\n", pkgPath, operation, pkgType)
	} else {
		result.Status = "pass"
		progressf("  %s pub %s (%s): ok\n", pkgPath, operation, pkgType)
	}

	return result
}
