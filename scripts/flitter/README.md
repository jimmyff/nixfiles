# flitter.rs

**Author**: [Jimmy Forrester-Fellowes](https://www.jimmyff.co.uk) (2025)

A Rust script for Flutter development with hot reloading and debug info capture.

## Usage

```bash
# Basic usage (current directory)
./flitter.rs

# Specify Flutter project path
./flitter.rs ~/my-flutter-app

# With Flutter arguments
./flitter.rs --flavor dev --verbose --device-id macos
```

## Features

- **Hot reloading**: Automatic reload on `.dart` file changes (300ms debouncing)
- **Debug info capture**: Extracts VM Service URLs and Firebase App Check tokens
- **Interactive controls**: `r` (reload), `R` (restart), `i` (debug info), `q` (quit)
- **Multiple instances**: Session-based isolation for concurrent Flutter sessions
- **Flutter passthrough**: Forwards all Flutter CLI arguments seamlessly
- **Robust cleanup**: Proper process and file cleanup on exit

## Requirements

- Rust with `rust-script` support
- Flutter SDK

## How it works

1. Generates unique session ID for PID file isolation
2. Starts Flutter with session-specific PID file
3. Watches `lib/**/*.dart` files for changes using efficient file system events
4. Sends hot reload signals to Flutter process
5. Captures and displays debug information (VM Service URLs, App Check tokens)
6. Provides interactive keyboard controls
7. Ensures clean process cleanup on exit