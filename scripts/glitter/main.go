package main

import (
	"fmt"
	"os"
	"glittering/cmd"
)

const helpText = `glittering — Dart/Flutter super-project orchestrator (JSON to stdout, logs to stderr)

Commands:
  status       List discovered packages (type, tests, dependencies)
  test         Run tests across all packages (parallel, cached)
  analyze      Run dart analyze across all packages (parallel, cached)
  get          Run pub get across all packages
  upgrade      Run pub upgrade across all packages
  git          Git status, check, push, commits, diffs across parent + submodules
  clean        Remove old session directories

Common flags:
  -path string    workspace root path (default ".")
  -filter string  comma-separated package name filters
  -cached         read from cache instead of running live

Run 'glittering <command> -help' for command-specific flags.
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, helpText)
		os.Exit(2)
	}

	args := os.Args[2:]
	switch os.Args[1] {
	case "-help", "--help", "help":
		fmt.Fprint(os.Stderr, helpText)
		os.Exit(0)
	case "status":
		os.Exit(cmd.Status(args))
	case "test":
		os.Exit(cmd.Test(args))
	case "analyze":
		os.Exit(cmd.Analyze(args))
	case "get":
		os.Exit(cmd.Get(args))
	case "upgrade":
		os.Exit(cmd.Upgrade(args))
	case "git":
		os.Exit(cmd.Git(args))
	case "clean":
		os.Exit(cmd.Clean(args))
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		fmt.Fprint(os.Stderr, helpText)
		os.Exit(2)
	}
}
