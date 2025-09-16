# flitter.nu

**Author**: [Jimmy Forrester-Fellowes](https://jimmyff.com) (2025)

A Nushell script for Flutter development with hot reloading and optional Doppler secrets management.

## Usage

```bash
# Basic usage (current directory)
nu flitter.nu

# Specify Flutter project path
nu flitter.nu ~/my-flutter-app

# With Doppler environment variables
nu flitter.nu --doppler-project my-app-dev

# Forward Flutter arguments
nu flitter.nu --flavor dev --verbose
nu flitter.nu ~/app --doppler-project prod --release
```

## Features

- **Hot reloading**: Watches `lib/**/*.dart` files and triggers hot reload on changes
- **Multiple instances**: Session-based PID files allow concurrent Flutter sessions
- **Doppler integration**: Optional environment variable loading from Doppler projects
- **Flutter passthrough**: Forwards all Flutter CLI arguments seamlessly

## Requirements

- Nushell
- Flutter SDK
- `entr` command (for file watching)
- `doppler` CLI (only when using `--doppler-project`)

## How it works

1. Generates unique session ID for PID file isolation
2. Optionally loads environment from Doppler project
3. Starts Flutter with session-specific PID file
4. Uses `entr` to watch for `.dart` file changes
5. Sends `SIGUSR1` signal to Flutter process for hot reload
6. Cleans up PID file on exit