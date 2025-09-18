#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! tokio = { version = "1.0", features = ["full"] }
//! clap = { version = "4.0", features = ["derive"] }
//! notify = "6.0"
//! crossterm = "0.27"
//! anyhow = "1.0"
//! regex = "1.0"
//! uuid = { version = "1.0", features = ["v4"] }
//! libc = "0.2"
//! ```
//!
//! # Flitter - Flutter Hot Reloader
//! 
//! **Author**: Jimmy Forrester-Fellowes <https://www.jimmyff.co.uk> (2025)
//! 
//! A Rust script for Flutter development with hot reloading, debug info capture,
//! and optional Doppler secrets management.

use std::{
    path::{Path, PathBuf},
    process::Stdio,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};

use anyhow::{anyhow, Context, Result};
use clap::Parser;
use crossterm::{
    execute,
    style::{Color, Print, ResetColor, SetForegroundColor},
};
use notify::{Config, Event as NotifyEvent, RecommendedWatcher, RecursiveMode, Watcher};
use regex::Regex;
use tokio::{
    fs,
    io::{AsyncBufReadExt, AsyncReadExt, BufReader},
    process::{Child, Command},
    sync::mpsc,
    time::sleep,
};
use uuid::Uuid;

// ============================================================================
// Types and Constants
// ============================================================================

#[derive(Parser)]
#[command(name = "flitter")]
#[command(about = "Flutter Hot Reloader with Optional Doppler Integration")]
#[command(version = "1.0.0")]
#[command(author = "Jimmy Forrester-Fellowes <https://www.jimmyff.co.uk>")]
struct Args {
    /// Path to Flutter project (defaults to current directory)
    #[arg(default_value = ".")]
    path: PathBuf,

    /// Doppler project for environment variables
    #[arg(long, short = 'd')]
    doppler_project: Option<String>,

    /// Flutter command (defaults to 'run')
    #[arg(long, short = 'c', default_value = "run")]
    command: String,

    /// Flutter build flavor
    #[arg(long)]
    flavor: Option<String>,

    /// Main entry point file
    #[arg(long, short = 't')]
    target: Option<String>,

    /// Target device ID
    #[arg(long)]
    device_id: Option<String>,

    /// Build in debug mode
    #[arg(long)]
    debug: bool,

    /// Build in profile mode
    #[arg(long)]
    profile: bool,

    /// Build in release mode
    #[arg(long)]
    release: bool,

    /// Enable verbose logging
    #[arg(long, short = 'v')]
    verbose: bool,

    /// Additional Flutter arguments
    #[arg(last = true)]
    flutter_args: Vec<String>,
}

#[derive(Debug, Clone, Default)]
struct DebugInfo {
    vm_service_url: Option<String>,
    app_check_token: Option<String>,
    device_info: Option<String>,
    build_mode: Option<String>,
    session_id: String,
    pid_file: String,
    project_path: String,
}

#[derive(Debug)]
enum AppEvent {
    FileChanged(PathBuf),
    FlutterOutput,
    FlutterExited(i32),
    HotReload,
    HotRestart,
    ShowInfo,
    Quit,
}

struct FlutterSession {
    process: Option<Child>,
    pid_file: PathBuf,
    debug_info: Arc<Mutex<DebugInfo>>,
    shutdown: Arc<AtomicBool>,
}

struct CleanupGuard {
    session: Arc<Mutex<Option<FlutterSession>>>,
}

impl CleanupGuard {
    fn new(session: FlutterSession) -> Self {
        Self {
            session: Arc::new(Mutex::new(Some(session))),
        }
    }

    async fn cleanup(&self) -> Result<()> {
        if let Some(mut session) = self.session.lock().unwrap().take() {
            session.cleanup().await?;
        }
        Ok(())
    }
}

impl Drop for CleanupGuard {
    fn drop(&mut self) {
        if let Some(mut session) = self.session.lock().unwrap().take() {
            // Synchronous cleanup - best effort
            print_info("Emergency cleanup on drop...");
            if session.pid_file.exists() {
                let _ = std::fs::remove_file(&session.pid_file);
            }
            if let Some(mut process) = session.process.take() {
                let _ = process.kill();
            }
        }
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

fn print_colored(color: Color, text: &str) {
    let _ = execute!(
        std::io::stderr(),
        SetForegroundColor(color),
        Print(text),
        ResetColor
    );
    eprintln!();
}

fn print_success(text: &str) {
    print_colored(Color::Green, &format!("✨ {}", text));
}

fn print_error(text: &str) {
    print_colored(Color::Red, &format!("❌ {}", text));
}

fn print_warning(text: &str) {
    print_colored(Color::Yellow, &format!("⚠️  {}", text));
}

fn print_info(text: &str) {
    print_colored(Color::Blue, &format!("👀 {}", text));
}

fn print_header(title: &str) {
    eprintln!();
    print_colored(Color::Magenta, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    print_colored(Color::Cyan, &format!("📱 {}", title));
    print_colored(Color::Magenta, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    eprintln!();
}

fn generate_session_id() -> String {
    Uuid::new_v4().to_string()[..8].to_string()
}

async fn check_prerequisites() -> Result<()> {
    // Check Flutter
    if Command::new("flutter")
        .arg("--version")
        .output()
        .await
        .is_err()
    {
        return Err(anyhow!("Flutter CLI not found. Please install Flutter SDK."));
    }

    Ok(())
}

async fn check_doppler() -> Result<()> {
    if Command::new("doppler")
        .arg("--version")
        .output()
        .await
        .is_err()
    {
        return Err(anyhow!("Doppler CLI not found. Please install Doppler CLI when using --doppler-project."));
    }

    Ok(())
}

fn validate_flutter_project(path: &Path) -> Result<()> {
    let lib_path = path.join("lib");
    if !lib_path.exists() {
        return Err(anyhow!(
            "No lib/ directory found in {}. Are you in a Flutter project?",
            path.display()
        ));
    }

    Ok(())
}

// ============================================================================
// Session Management
// ============================================================================

impl FlutterSession {
    fn new(session_id: String, project_path: PathBuf) -> Self {
        let pid_file = PathBuf::from(format!("/tmp/flutter-{}.pid", session_id));
        
        let debug_info = DebugInfo {
            session_id: session_id.clone(),
            pid_file: pid_file.to_string_lossy().to_string(),
            project_path: project_path.to_string_lossy().to_string(),
            ..Default::default()
        };

        Self {
            process: None,
            pid_file,
            debug_info: Arc::new(Mutex::new(debug_info)),
            shutdown: Arc::new(AtomicBool::new(false)),
        }
    }

    async fn cleanup(&mut self) -> Result<()> {
        print_info("Cleaning up processes and files...");

        // Kill Flutter process
        if let Some(mut process) = self.process.take() {
            let _ = process.kill().await;
        }

        // Remove PID file
        if self.pid_file.exists() {
            if let Ok(pid_content) = fs::read_to_string(&self.pid_file).await {
                if let Ok(pid) = pid_content.trim().parse::<u32>() {
                    // Try to kill the process
                    #[cfg(unix)]
                    {
                        unsafe {
                            libc::kill(pid as i32, libc::SIGTERM);
                        }
                    }
                }
            }
            let _ = fs::remove_file(&self.pid_file).await;
        }

        print_success("Cleanup completed");
        Ok(())
    }
}

// ============================================================================
// Output Parser
// ============================================================================

struct OutputParser {
    vm_service_regex: Regex,
    app_check_regex: Regex,
    device_regex: Regex,
}

impl OutputParser {
    fn new() -> Result<Self> {
        Ok(Self {
            vm_service_regex: Regex::new(r"A Dart VM Service .* is available at: (http://[^\s]+)")?,
            app_check_regex: Regex::new(r"Firebase App Check Debug Token: ([A-F0-9-]+)")?,
            device_regex: Regex::new(r"Launching .* on (.+?) in debug mode")?,
        })
    }

    fn parse_line(&self, line: &str, debug_info: &Arc<Mutex<DebugInfo>>) {
        let mut info = debug_info.lock().unwrap();

        if let Some(captures) = self.vm_service_regex.captures(line) {
            info.vm_service_url = Some(captures[1].to_string());
            print_success(&format!("Captured VM Service URL: {}", &captures[1]));
        }

        if let Some(captures) = self.app_check_regex.captures(line) {
            info.app_check_token = Some(captures[1].to_string());
            print_success(&format!("Captured App Check Token: {}", &captures[1]));
        }

        if let Some(captures) = self.device_regex.captures(line) {
            info.device_info = Some(captures[1].to_string());
        }

        if line.contains("debug mode") {
            info.build_mode = Some("debug".to_string());
        } else if line.contains("profile mode") {
            info.build_mode = Some("profile".to_string());
        } else if line.contains("release mode") {
            info.build_mode = Some("release".to_string());
        }
    }
}

// ============================================================================
// Flutter Process Management
// ============================================================================

async fn start_flutter_process(
    args: &Args,
    session: &mut FlutterSession,
    event_tx: mpsc::UnboundedSender<AppEvent>,
) -> Result<()> {
    // Build Flutter command
    let mut cmd = if let Some(doppler_project) = &args.doppler_project {
        check_doppler().await?;
        let mut cmd = Command::new("doppler");
        cmd.args(&["run", "--project", doppler_project, "--"]);
        cmd.arg("flutter");
        cmd
    } else {
        Command::new("flutter")
    };

    cmd.arg(&args.command);
    cmd.arg("--pid-file").arg(&session.pid_file);

    // Add Flutter arguments
    if let Some(flavor) = &args.flavor {
        cmd.args(&["--flavor", flavor]);
    }
    if let Some(target) = &args.target {
        cmd.args(&["--target", target]);
    }
    if let Some(device_id) = &args.device_id {
        cmd.args(&["--device-id", device_id]);
    }
    if args.debug {
        cmd.arg("--debug");
    }
    if args.profile {
        cmd.arg("--profile");
    }
    if args.release {
        cmd.arg("--release");
    }
    if args.verbose {
        cmd.arg("--verbose");
    }

    // Add additional arguments
    cmd.args(&args.flutter_args);

    // Set working directory
    cmd.current_dir(&args.path);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    print_info(&format!("Starting Flutter: {:?}", cmd));

    // Start the process
    let mut child = cmd.spawn().context("Failed to start Flutter process")?;
    
    // Get stdout and stderr
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    session.process = Some(child);

    // Spawn output readers
    let debug_info = session.debug_info.clone();
    let event_tx_stdout = event_tx.clone();
    let event_tx_stderr = event_tx.clone();

    tokio::spawn(async move {
        let parser = OutputParser::new().unwrap();
        let mut reader = BufReader::new(stdout);
        let mut line = String::new();

        while reader.read_line(&mut line).await.unwrap_or(0) > 0 {
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                parser.parse_line(trimmed, &debug_info);
                let _ = event_tx_stdout.send(AppEvent::FlutterOutput);
                print!("{}", line);
            }
            line.clear();
        }
    });

    tokio::spawn(async move {
        let mut reader = BufReader::new(stderr);
        let mut line = String::new();

        while reader.read_line(&mut line).await.unwrap_or(0) > 0 {
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                let _ = event_tx_stderr.send(AppEvent::FlutterOutput);
                eprint!("{}", line);
            }
            line.clear();
        }
    });

    // Wait for PID file to be created
    print_info("Waiting for Flutter to create PID file...");
    for i in 0..60 {
        if session.pid_file.exists() {
            print_success("Flutter started successfully!");
            return Ok(());
        }
        if i % 10 == 0 {
            print_info(&format!("Still waiting for PID file... ({}/60)", i + 1));
        }
        sleep(Duration::from_secs(1)).await;
    }

    Err(anyhow!("Flutter failed to start - PID file not created"))
}

async fn send_signal_to_flutter(pid_file: &Path, signal: i32) -> Result<()> {
    if !pid_file.exists() {
        return Err(anyhow!("PID file not found"));
    }

    let pid_content = fs::read_to_string(pid_file).await?;
    let pid: u32 = pid_content.trim().parse()?;

    #[cfg(unix)]
    {
        unsafe {
            if libc::kill(pid as i32, signal) == 0 {
                Ok(())
            } else {
                Err(anyhow!("Failed to send signal to Flutter process"))
            }
        }
    }

    #[cfg(not(unix))]
    {
        Err(anyhow!("Signal sending not supported on this platform"))
    }
}

// ============================================================================
// File Watcher
// ============================================================================

async fn setup_file_watcher(
    project_path: &Path,
    event_tx: mpsc::UnboundedSender<AppEvent>,
) -> Result<()> {
    let (file_tx, mut file_rx) = mpsc::unbounded_channel();
    let lib_path = project_path.join("lib");

    let mut watcher = RecommendedWatcher::new(
        move |res: Result<NotifyEvent, notify::Error>| {
            if let Ok(event) = res {
                if let Some(path) = event.paths.first() {
                    if path.extension().map_or(false, |ext| ext == "dart") {
                        let _ = file_tx.send(path.clone());
                    }
                }
            }
        },
        Config::default(),
    )?;

    watcher.watch(&lib_path, RecursiveMode::Recursive)?;

    print_info(&format!("Watching for changes in {}/", lib_path.display()));

    // Debouncing logic
    let mut last_change = Instant::now();
    let debounce_duration = Duration::from_millis(300);

    tokio::spawn(async move {
        let _watcher = watcher; // Keep watcher alive
        
        while let Some(path) = file_rx.recv().await {
            let now = Instant::now();
            if now.duration_since(last_change) >= debounce_duration {
                last_change = now;
                let _ = event_tx.send(AppEvent::FileChanged(path));
            }
        }
    });

    Ok(())
}

// ============================================================================
// Keyboard Handler
// ============================================================================

async fn setup_keyboard_handler(event_tx: mpsc::UnboundedSender<AppEvent>) -> Result<()> {
    tokio::spawn(async move {
        let mut stdin = tokio::io::stdin();
        let mut buffer = [0u8; 1];
        
        loop {
            tokio::select! {
                result = stdin.read(&mut buffer) => {
                    if let Ok(1) = result {
                        let key = buffer[0] as char;
                        let event = match key {
                            'r' => AppEvent::HotReload,
                            'R' => AppEvent::HotRestart,
                            'i' => AppEvent::ShowInfo,
                            'q' | '\x03' => AppEvent::Quit, // 'q' or Ctrl+C
                            _ => continue,
                        };
                        let _ = event_tx.send(event);
                    }
                }
                _ = tokio::time::sleep(Duration::from_millis(100)) => {
                    // Continue polling
                }
            }
        }
    });

    Ok(())
}

fn display_debug_info(debug_info: &DebugInfo) {
    print_header("Debug Information");
    
    eprintln!("📋 Session: {}", debug_info.session_id);
    eprintln!("📁 Project: {}", debug_info.project_path);
    eprintln!("📄 PID File: {}", debug_info.pid_file);
    
    if let Some(mode) = &debug_info.build_mode {
        eprintln!("🔧 Build Mode: {}", mode);
    }
    
    if let Some(device) = &debug_info.device_info {
        eprintln!("📱 Device: {}", device);
    }
    
    if let Some(url) = &debug_info.vm_service_url {
        eprintln!("🌐 VM Service: {}", url);
    }
    
    if let Some(token) = &debug_info.app_check_token {
        eprintln!("🔐 App Check Token: {}", token);
    }
    
    eprintln!();
    print_info("Press any key to continue...");
}

// ============================================================================
// Main Function
// ============================================================================

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    print_header("Flitter - Flutter Hot Reloader");

    // Check prerequisites
    check_prerequisites().await?;
    
    // Validate project
    let project_path = args.path.canonicalize()?;
    validate_flutter_project(&project_path)?;

    // Generate session
    let session_id = generate_session_id();
    let session = FlutterSession::new(session_id.clone(), project_path.clone());

    print_info(&format!("Session ID: {}", session_id));
    print_info(&format!("Project: {}", project_path.display()));

    // Setup cleanup guard
    let cleanup_guard = CleanupGuard::new(session);
    
    // Get session reference for operations
    let session_guard = cleanup_guard.session.clone();
    let mut session_ref = session_guard.lock().unwrap();
    let session = session_ref.as_mut().unwrap();

    // Setup channels
    let (event_tx, mut event_rx) = mpsc::unbounded_channel();

    // Setup signal handler
    let shutdown = session.shutdown.clone();
    tokio::spawn(async move {
        let _ = tokio::signal::ctrl_c().await;
        shutdown.store(true, Ordering::Relaxed);
    });

    // Start Flutter process
    start_flutter_process(&args, session, event_tx.clone()).await?;

    // Setup file watcher
    setup_file_watcher(&project_path, event_tx.clone()).await?;

    // Setup keyboard handler (no raw mode needed)
    setup_keyboard_handler(event_tx.clone()).await?;

    print_info("Hot reload ready!");
    eprintln!("Controls: [r] Hot Reload | [R] Hot Restart | [i] Debug Info | [q] Quit");
    eprintln!();

    // Main event loop
    let shutdown_flag = session.shutdown.clone();
    let session_debug_info = session.debug_info.clone();
    let session_pid_file = session.pid_file.clone();
    
    // Release the session lock before the event loop
    drop(session_ref);
    
    while !shutdown_flag.load(Ordering::Relaxed) {
        tokio::select! {
            Some(event) = event_rx.recv() => {
                match event {
                    AppEvent::FileChanged(path) => {
                        print_info(&format!("🔥 File changed: {}", path.display()));
                        if let Err(e) = send_signal_to_flutter(&session_pid_file, libc::SIGUSR1).await {
                            print_warning(&format!("Hot reload failed: {}", e));
                        } else {
                            print_success("Hot reload triggered");
                        }
                    }
                    AppEvent::HotReload => {
                        if let Err(e) = send_signal_to_flutter(&session_pid_file, libc::SIGUSR1).await {
                            print_warning(&format!("Hot reload failed: {}", e));
                        } else {
                            print_success("Hot reload triggered");
                        }
                    }
                    AppEvent::HotRestart => {
                        if let Err(e) = send_signal_to_flutter(&session_pid_file, libc::SIGUSR2).await {
                            print_warning(&format!("Hot restart failed: {}", e));
                        } else {
                            print_success("Hot restart triggered");
                        }
                    }
                    AppEvent::ShowInfo => {
                        let info = session_debug_info.lock().unwrap().clone();
                        display_debug_info(&info);
                    }
                    AppEvent::Quit => {
                        break;
                    }
                    AppEvent::FlutterOutput => {
                        // Already handled in the output reader
                    }
                    AppEvent::FlutterExited(code) => {
                        print_error(&format!("Flutter process exited with code: {}", code));
                        break;
                    }
                }
            }
            _ = sleep(Duration::from_millis(100)) => {
                // Check if Flutter process is still running
                if let Some(session) = session_guard.lock().unwrap().as_mut() {
                    if let Some(process) = &mut session.process {
                        if let Ok(Some(exit_status)) = process.try_wait() {
                            let code = exit_status.code().unwrap_or(-1);
                            let _ = event_tx.send(AppEvent::FlutterExited(code));
                        }
                    }
                }
            }
        }
    }

    // Cleanup using the guard
    cleanup_guard.cleanup().await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_output_parser() {
        let parser = OutputParser::new().unwrap();
        let debug_info = Arc::new(Mutex::new(DebugInfo::default()));

        // Test VM Service URL parsing
        parser.parse_line(
            "A Dart VM Service on macOS is available at: http://127.0.0.1:52195/6p6i7h7yeS0=/",
            &debug_info,
        );
        assert_eq!(
            debug_info.lock().unwrap().vm_service_url,
            Some("http://127.0.0.1:52195/6p6i7h7yeS0=/".to_string())
        );

        // Test App Check token parsing
        parser.parse_line(
            "Firebase App Check Debug Token: 493FE8A7-0EA0-490D-AAE0-0891CC66C473",
            &debug_info,
        );
        assert_eq!(
            debug_info.lock().unwrap().app_check_token,
            Some("493FE8A7-0EA0-490D-AAE0-0891CC66C473".to_string())
        );
    }

    #[test]
    fn test_session_id_generation() {
        let id1 = generate_session_id();
        let id2 = generate_session_id();
        assert_ne!(id1, id2);
        assert_eq!(id1.len(), 8);
    }
}