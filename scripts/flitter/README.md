# flitter.rs

**Author**: [Jimmy Forrester-Fellowes](https://www.jimmyff.co.uk) (2025)

A Rust script for Flutter development with hot reloading, debug info capture, and optional Doppler secrets management.

## Usage

```bash
# Basic usage (current directory)
./flitter.rs

# Specify Flutter project path
./flitter.rs ~/my-flutter-app

# With Doppler environment variables
./flitter.rs --doppler-project my-app-dev

# With Flutter arguments
./flitter.rs --flavor dev --verbose --device-id macos
```

## Features

- **Hot reloading**: Automatic reload on `.dart` file changes (300ms debouncing)
- **Debug info capture**: Extracts VM Service URLs and Firebase App Check tokens
- **Interactive controls**: `r` (reload), `R` (restart), `i` (debug info), `q` (quit)
- **Multiple instances**: Session-based isolation for concurrent Flutter sessions
- **Doppler integration**: Optional environment variable loading
- **Flutter passthrough**: Forwards all Flutter CLI arguments seamlessly
- **Robust cleanup**: Proper process and file cleanup on exit

## Requirements

- Rust with `rust-script` support
- Flutter SDK
- `doppler` CLI (only when using `--doppler-project`)

## How it works

1. Generates unique session ID for PID file isolation
2. Optionally loads environment from Doppler project  
3. Starts Flutter with session-specific PID file
4. Watches `lib/**/*.dart` files for changes using efficient file system events
5. Sends hot reload signals to Flutter process
6. Captures and displays debug information (VM Service URLs, App Check tokens)
7. Provides interactive keyboard controls
8. Ensures clean process cleanup on exit