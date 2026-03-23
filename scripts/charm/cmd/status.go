package cmd

import "flag"

// Status discovers Dart/Flutter packages and outputs their metadata.
func Status(args []string) int {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	path := fs.String("path", ".", "workspace root path")
	filter := fs.String("filter", "", "comma-separated package name filters")
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

	logf("charm: found %d packages\n", len(packages))

	out := StatusOutput{Packages: packages}
	if out.Packages == nil {
		out.Packages = []PackageInfo{}
	}
	if err := outputJSON(out); err != nil {
		logf("error: %v\n", err)
		return ExitFailure
	}
	return ExitOK
}
