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
//! nix = { version = "0.29", features = ["signal", "process"] }
//! ```
//!
//! # Flitter - Flutter Hot Reloader
//! 
//! **Author**: Jimmy Forrester-Fellowes <https://www.jimmyff.co.uk> (2025)
//! 
//! A Rust script for Flutter development with hot reloading and debug info capture.

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
use nix::{
    sys::signal::{self, Signal},
    unistd::{setsid, Pid},
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
#[command(about = "Flutter Hot Reloader")]
#[command(version = "1.0.0")]
#[command(author = "Jimmy Forrester-Fellowes <https://www.jimmyff.co.uk>")]
struct Args {
    /// Path to Flutter project (defaults to current directory)
    #[arg(default_value = ".")]
    path: PathBuf,


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

    /// Strip flutter log prefixes from output
    #[arg(long, default_value = "true")]
    strip_flutter_prefix: bool,

    /// Additional Flutter arguments
    #[arg(last = true)]
    flutter_args: Vec<String>,
}

#[derive(Debug, Clone, Default)]
struct DebugInfo {
    vm_service_url: Option<String>,
    devtools_url: Option<String>,
    app_check_token: Option<String>,
    device_info: Option<String>,
    device_id: Option<String>,
    build_mode: Option<String>,
    android_log_pid: Option<String>,
    session_id: String,
    pid_file: String,
    project_path: String,
    process_group_id: Option<Pid>,
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
            
            // Try to terminate process group synchronously
            if let Some(pgid) = session.debug_info.lock().unwrap().process_group_id {
                #[cfg(unix)]
                {
                    // Emergency kill - use SIGKILL directly
                    let _ = signal::killpg(pgid, Signal::SIGKILL);
                }
            }
            
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
    print_colored(Color::Green, &format!("✅ {}", text));
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
    print_colored(Color::Magenta, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    print_colored(Color::Cyan, &format!("📱 {}", title));
    print_colored(Color::Magenta, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    eprintln!();
}

fn generate_session_id() -> String {
    Uuid::new_v4().to_string()[..8].to_string()
}

fn get_relative_path(absolute_path: &Path, project_root: &Path) -> String {
    absolute_path
        .strip_prefix(project_root)
        .unwrap_or(absolute_path)
        .to_string_lossy()
        .to_string()
}

fn get_timestamp() -> String {
    use std::time::SystemTime;
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    
    let hours = (now / 3600) % 24;
    let minutes = (now / 60) % 60;
    let seconds = now % 60;
    
    format!("{:02}:{:02}:{:02}", hours, minutes, seconds)
}

fn clean_flutter_log_line(line: &str, debug_info: &Arc<Mutex<DebugInfo>>) -> String {
    // Check for Android format: [LEVEL]/flutter (PID): message
    if let Some(captures) = Regex::new(r"^([DWIEV])/flutter \((\d+)\): (.*)$").unwrap().captures(line) {
        let log_level = &captures[1];
        let pid = &captures[2];
        let message = &captures[3];
        
        // Store PID if we haven't captured it yet
        {
            let mut info = debug_info.lock().unwrap();
            if info.android_log_pid.is_none() {
                info.android_log_pid = Some(pid.to_string());
            }
        }
        
        // Convert log level to emoji
        let emoji = match log_level {
            "I" => "ⓘ",
            "D" => "🐛",
            "W" => "⚠️",
            "E" => "❌",
            "V" => "🔍",
            _ => "📝", // fallback
        };
        
        format!("{} {}", emoji, message)
    }
    // Check for macOS format: flutter: message
    else if let Some(captures) = Regex::new(r"^flutter: (.*)$").unwrap().captures(line) {
        captures[1].to_string()
    }
    // Return original line if it doesn't match any known format
    else {
        line.to_string()
    }
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
    fn new(session_id: String, project_path: PathBuf, device_id: Option<String>) -> Self {
        let pid_file = PathBuf::from(format!("/tmp/flutter-{}.pid", session_id));
        
        let debug_info = DebugInfo {
            session_id: session_id.clone(),
            pid_file: pid_file.to_string_lossy().to_string(),
            project_path: project_path.to_string_lossy().to_string(),
            device_id,
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

        // Terminate Flutter process group first
        if let Err(e) = terminate_flutter_process_group(&self.debug_info).await {
            print_warning(&format!("Process group termination failed: {}", e));
            
            // Fallback: Kill Flutter process directly
            if let Some(mut process) = self.process.take() {
                let _ = process.kill().await;
            }
        }

        // Remove PID file
        if self.pid_file.exists() {
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
    devtools_regex: Regex,
    app_check_regex: Regex,
    device_regex: Regex,
}

impl OutputParser {
    fn new() -> Result<Self> {
        Ok(Self {
            vm_service_regex: Regex::new(r"A Dart VM Service .* is available at: (http://[^\s]+)")?,
            devtools_regex: Regex::new(r"The Flutter DevTools.*?is available at: (http://[^\s]+)")?,
            app_check_regex: Regex::new(r"Enter this debug secret into the allow list.*?: ([a-f0-9-]+)")?,
            device_regex: Regex::new(r"Launching .* on (.+?) in (\w+) mode")?,
        })
    }

    fn parse_line(&self, line: &str, debug_info: &Arc<Mutex<DebugInfo>>) {
        let mut info = debug_info.lock().unwrap();

        if let Some(captures) = self.vm_service_regex.captures(line) {
            info.vm_service_url = Some(captures[1].to_string());
            print_success(&format!("Captured VM Service URL: {}", &captures[1]));
        }

        if let Some(captures) = self.devtools_regex.captures(line) {
            info.devtools_url = Some(captures[1].to_string());
            print_success(&format!("Captured DevTools URL: {}", &captures[1]));
        }

        if let Some(captures) = self.app_check_regex.captures(line) {
            info.app_check_token = Some(captures[1].to_string());
            print_success(&format!("Captured Firebase App Check Token: {}", &captures[1]));
        }

        if let Some(captures) = self.device_regex.captures(line) {
            info.device_info = Some(captures[1].to_string());
            info.build_mode = Some(captures[2].to_string());
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
    let mut cmd = Command::new("flutter");

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

    // Create new process group for proper cleanup
    #[cfg(unix)]
    unsafe {
        cmd.pre_exec(|| {
            setsid().map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
            Ok(())
        });
    }

    print_info(&format!("Starting Flutter: {:?}", cmd));

    // Start the process
    let mut child = cmd.spawn().context("Failed to start Flutter process")?;
    
    // Store process group ID for cleanup
    #[cfg(unix)]
    {
        let pid = child.id().unwrap();
        session.debug_info.lock().unwrap().process_group_id = Some(Pid::from_raw(pid as i32));
    }
    
    // Get stdout and stderr
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    session.process = Some(child);

    // Spawn output readers
    let debug_info = session.debug_info.clone();
    let debug_info_stderr = session.debug_info.clone();
    let event_tx_stdout = event_tx.clone();
    let event_tx_stderr = event_tx.clone();
    let strip_prefix = args.strip_flutter_prefix;

    tokio::spawn(async move {
        let parser = OutputParser::new().unwrap();
        let mut reader = BufReader::new(stdout);
        let mut line = String::new();

        while reader.read_line(&mut line).await.unwrap_or(0) > 0 {
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                parser.parse_line(trimmed, &debug_info);
                let _ = event_tx_stdout.send(AppEvent::FlutterOutput);
                
                if strip_prefix {
                    let cleaned = clean_flutter_log_line(trimmed, &debug_info);
                    println!("{}", cleaned);
                } else {
                    print!("{}", line);
                }
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
                
                if strip_prefix {
                    let cleaned = clean_flutter_log_line(trimmed, &debug_info_stderr);
                    eprintln!("{}", cleaned);
                } else {
                    eprint!("{}", line);
                }
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

async fn send_signal_to_flutter(pid_file: &Path, sig: Signal) -> Result<()> {
    if !pid_file.exists() {
        return Err(anyhow!("PID file not found"));
    }

    let pid_content = fs::read_to_string(pid_file).await?;
    let pid: u32 = pid_content.trim().parse()?;

    #[cfg(unix)]
    {
        signal::kill(Pid::from_raw(pid as i32), sig)
            .map_err(|e| anyhow!("Failed to send signal to Flutter process: {}", e))
    }

    #[cfg(not(unix))]
    {
        Err(anyhow!("Signal sending not supported on this platform"))
    }
}

async fn terminate_flutter_process_group(debug_info: &Arc<Mutex<DebugInfo>>) -> Result<()> {
    let info = debug_info.lock().unwrap();
    let pgid = match info.process_group_id {
        Some(id) => id,
        None => return Err(anyhow!("No process group ID available")),
    };
    drop(info);

    #[cfg(unix)]
    {
        // First try graceful shutdown with SIGTERM
        print_info("Sending SIGTERM to Flutter process group...");
        signal::killpg(pgid, Signal::SIGTERM)
            .map_err(|e| anyhow!("Failed to send SIGTERM to process group: {}", e))?;

        // Wait for graceful shutdown
        sleep(Duration::from_millis(300)).await;

        // Check if process group still exists by sending signal 0
        match signal::killpg(pgid, None) {
            Ok(()) => {
                // Process group still exists, force kill
                print_warning("Process group still running, sending SIGKILL...");
                signal::killpg(pgid, Signal::SIGKILL)
                    .map_err(|e| anyhow!("Failed to send SIGKILL to process group: {}", e))?;
            }
            Err(_) => {
                // Process group doesn't exist anymore, which is what we want
            }
        }

        print_success("Flutter process group terminated");
        Ok(())
    }

    #[cfg(not(unix))]
    {
        Err(anyhow!("Process group termination not supported on this platform"))
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
            match res {
                Ok(event) => {
                    if let Some(path) = event.paths.first() {
                        if path.extension().map_or(false, |ext| ext == "dart") {
                            if let Err(_) = file_tx.send(path.clone()) {
                                print_warning("Failed to send file change event");
                            }
                        }
                    }
                }
                Err(e) => {
                    print_warning(&format!("File watcher error: {}", e));
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
        print_info("File watcher task started");
        
        loop {
            match file_rx.recv().await {
                Some(path) => {
                    let now = Instant::now();
                    if now.duration_since(last_change) >= debounce_duration {
                        last_change = now;
                        let _ = event_tx.send(AppEvent::FileChanged(path));
                    }
                }
                None => {
                    print_warning("File watcher channel closed, task exiting");
                    break;
                }
            }
        }
        print_warning("File watcher task terminated");
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
    
    match (&debug_info.android_log_pid, &debug_info.build_mode) {
        (Some(pid), Some(mode)) => eprintln!("📋 ID: {} / PID: {} / 🔧 {}", debug_info.session_id, pid, mode.to_uppercase()),
        (Some(pid), None) => eprintln!("📋 ID: {} / PID: {}", debug_info.session_id, pid),
        (None, Some(mode)) => eprintln!("📋 ID: {} / 🔧 {}", debug_info.session_id, mode.to_uppercase()),
        (None, None) => eprintln!("📋 ID: {}", debug_info.session_id),
    }
    eprintln!("📁 Project Path: {}", debug_info.project_path);
    eprintln!("📄 PID File: {}", debug_info.pid_file);
    
    if let Some(device) = &debug_info.device_info {
        match &debug_info.device_id {
            Some(device_id) => eprintln!("📱 Device: {} ({})", device, device_id),
            None => eprintln!("📱 Device: {}", device),
        }
    }
    
    if let Some(url) = &debug_info.vm_service_url {
        eprintln!("🌐 VM Service: {}", url);
    }
    
    if let Some(url) = &debug_info.devtools_url {
        eprintln!("🛠️ DevTools: {}", url);
    }
    
    if let Some(token) = &debug_info.app_check_token {
        eprintln!("🔐 Firebase App Check Token: {}", token);
    }
    
    eprintln!();
    eprintln!();
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
    let session = FlutterSession::new(session_id.clone(), project_path.clone(), args.device_id.clone());

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
                        eprintln!();
                        print_colored(Color::Red, &format!("🔥 {}", get_relative_path(&path, &project_path)));
                        if let Err(e) = send_signal_to_flutter(&session_pid_file, Signal::SIGUSR1).await {
                            print_warning(&format!("Hot reload failed: {}", e));
                        } else {
                            print_success(&format!("Hot reload triggered ({})", get_timestamp()));
                        }
                        eprintln!();
                    }
                    AppEvent::HotReload => {
                        eprintln!();
                        print_colored(Color::Red, "🔥 Manual hot reload");
                        if let Err(e) = send_signal_to_flutter(&session_pid_file, Signal::SIGUSR1).await {
                            print_warning(&format!("Hot reload failed: {}", e));
                        } else {
                            print_success(&format!("Hot reload triggered ({})", get_timestamp()));
                        }
                        eprintln!();
                    }
                    AppEvent::HotRestart => {
                        // Clear console before restart
                        print!("\x1B[2J\x1B[1;1H");
                        print_colored(Color::Blue, "🔄 Manual hot restart");
                        if let Err(e) = send_signal_to_flutter(&session_pid_file, Signal::SIGUSR2).await {
                            print_warning(&format!("Hot restart failed: {}", e));
                        } else {
                            print_success(&format!("Hot restart triggered ({})", get_timestamp()));
                        }
                        eprintln!();
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
            "A Dart VM Service on Pixel 5 is available at: http://127.0.0.1:52195/6p6i7h7yeS0=/",
            &debug_info,
        );
        assert_eq!(
            debug_info.lock().unwrap().vm_service_url,
            Some("http://127.0.0.1:52195/6p6i7h7yeS0=/".to_string())
        );

        // Test DevTools URL parsing
        parser.parse_line(
            "The Flutter DevTools debugger and profiler on Pixel 5 is available at: http://127.0.0.1:9107?uri=http://127.0.0.1:49585/gpYYaPaI9xM=/",
            &debug_info,
        );
        assert_eq!(
            debug_info.lock().unwrap().devtools_url,
            Some("http://127.0.0.1:9107?uri=http://127.0.0.1:49585/gpYYaPaI9xM=/".to_string())
        );

        // Test App Check token parsing (new format)
        parser.parse_line(
            "Enter this debug secret into the allow list in the Firebase Console for your project: 3df0581b-bd02-4109-91b0-1c202ff762eb",
            &debug_info,
        );
        assert_eq!(
            debug_info.lock().unwrap().app_check_token,
            Some("3df0581b-bd02-4109-91b0-1c202ff762eb".to_string())
        );

        // Test device and build mode parsing
        parser.parse_line(
            "Launching lib/entrypoint_onescene.dart on Pixel 5 in debug mode...",
            &debug_info,
        );
        assert_eq!(
            debug_info.lock().unwrap().device_info,
            Some("Pixel 5".to_string())
        );
        assert_eq!(
            debug_info.lock().unwrap().build_mode,
            Some("debug".to_string())
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