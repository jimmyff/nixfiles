# dartboard.nu

**Author**: [Jimmy Forrester-Fellowes](https://jimmyff.com) (2025)

A Nushell script for managing multiple Flutter/Dart projects. Discovers all projects with `pubspec.yaml` files and runs batch operations.

## Usage

```bash
# Show all projects
nu dartboard.nu --status
nu dartboard.nu ~/workspace -s

# Run operations
nu dartboard.nu --update           # flutter pub get on all projects
nu dartboard.nu --upgrade          # flutter pub upgrade on all projects  
nu dartboard.nu --test             # flutter test on all projects

# Interactive mode (choose operation)
nu dartboard.nu
nu dartboard.nu ~/workspace
```

## Features

- **Project discovery**: Finds all Flutter/Dart projects using `fd pubspec.yaml`
- **Batch operations**: Update, upgrade, or test multiple projects at once
- **Visual progress**: Shows real-time progress with success/error status
- **Project insights**: Displays project type, dependency counts, and paths

## Example Output

```
🎯 Dart/Flutter Projects
Found: 8 projects | Flutter: 5 | Dart: 3

╭───┬─────────────────────┬─────────┬──────┬──────────────────────╮
│ # │       Project       │  Type   │ Deps │         Path         │
├───┼─────────────────────┼─────────┼──────┼──────────────────────┤
│ 0 │ 📱 My Flutter App   │ Flutter │  45  │ ~/dev/app            │
│ 1 │ 🎯 CLI Tool         │ Dart    │  12  │ ~/dev/cli            │
╰───┴─────────────────────┴─────────┴──────┴──────────────────────╯
```

## Requirements

- Nushell
- Flutter SDK
- `fd` command (for file discovery)