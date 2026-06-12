package cmd

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// discoverPackages walks root to find Dart/Flutter packages (dirs with pubspec.yaml).
// Returns relative paths from root. Applies filter if non-empty.
func discoverPackages(root string, filters []string) ([]PackageInfo, error) {
	var packages []PackageInfo
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() {
			return nil
		}
		name := info.Name()
		if strings.HasPrefix(name, ".") || skipDirs[name] {
			return filepath.SkipDir
		}
		pubspec := filepath.Join(path, "pubspec.yaml")
		if _, err := os.Stat(pubspec); err != nil {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}
		pkg := parsePubspec(pubspec, rel)
		packages = append(packages, pkg)
		return nil
	})
	if err != nil {
		return nil, err
	}
	if len(filters) == 0 {
		return packages, nil
	}
	var filtered []PackageInfo
	for _, pkg := range packages {
		for _, f := range filters {
			if strings.Contains(pkg.Path, f) {
				filtered = append(filtered, pkg)
				break
			}
		}
	}
	return filtered, nil
}

// parsePubspec extracts package metadata from a pubspec.yaml file.
// Uses simple line scanning rather than a full YAML parser.
func parsePubspec(path, relPath string) PackageInfo {
	pkg := PackageInfo{
		Path: relPath,
		Name: filepath.Base(relPath),
		Type: "dart",
	}

	// Check for test directory
	testDir := filepath.Join(filepath.Dir(path), "test")
	if stat, err := os.Stat(testDir); err == nil && stat.IsDir() {
		pkg.HasTests = true
	}

	f, err := os.Open(path)
	if err != nil {
		return pkg
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	var currentSection string
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		// Top-level keys (no leading whitespace)
		if len(line) > 0 && line[0] != ' ' && line[0] != '\t' && strings.Contains(line, ":") {
			key := strings.TrimSuffix(strings.TrimSpace(strings.SplitN(line, ":", 2)[0]), " ")
			switch key {
			case "name":
				val := strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
				if val != "" {
					pkg.Name = val
				}
			case "dependencies":
				currentSection = "dependencies"
				continue
			case "dev_dependencies":
				currentSection = "dev_dependencies"
				continue
			default:
				currentSection = ""
			}
			continue
		}

		// Count section entries (indented lines with a colon)
		if currentSection != "" && (strings.HasPrefix(line, "  ") || strings.HasPrefix(line, "\t")) {
			if strings.Contains(trimmed, ":") && !strings.HasPrefix(trimmed, "#") {
				depName := strings.TrimSpace(strings.SplitN(trimmed, ":", 2)[0])
				switch currentSection {
				case "dependencies":
					pkg.Dependencies++
					if depName == "flutter" {
						pkg.Type = "flutter"
					}
				case "dev_dependencies":
					pkg.DevDependencies++
					if depName == "flutter_test" {
						pkg.Type = "flutter"
					}
				}
			}
		}
	}

	return pkg
}
