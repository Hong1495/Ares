import Foundation
import OSLog

/// Actor-based Clash service - properly isolated from MainActor
/// Replaces @MainActor ClashService to prevent Signal 9 watchdog kills
/// Uses async file I/O and process management to avoid blocking
actor ClashServiceActor {
    // MARK: - Singleton
    static let shared = ClashServiceActor()
    
    // MARK: - Dependencies
    private let fileManager = AsyncFileManager()
    private let processManager = ProcessManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.ares", category: "ClashServiceActor")
    
    // MARK: - State (Private, Actor-Isolated)
    private var isRunning: Bool = false
    private var process: Process?
    private var pipe: Pipe?
    private var currentProcessPID: Int32?
    
    // MARK: - Configuration
    private var configDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Ares/clash")
    }
    
    private var binaryPath: String {
        Bundle.main.path(forResource: "clash-meta", ofType: nil) ?? "/usr/local/bin/clash-meta"
    }
    
    // MARK: - Initialization
    private init() {
        Task {
            await createConfigDirIfNeeded()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start Clash process
    /// - Parameter isRestart: If true, bypasses "already running" check
    func start(isRestart: Bool = false) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        addLog("[ClashServiceActor] 🚀 Starting Clash...")
        
        // Check if already running
        if !isRestart && isRunning {
            addLog("[ClashServiceActor] ⚠️ Already running")
            return
        }
        
        // Clean up any zombie processes
        addLog("[ClashServiceActor] 🧹 Cleaning up old processes...")
        let cleanupSuccess = await cleanupOldProcesses()
        if !cleanupSuccess {
            addLog("[ClashServiceActor] ❌ Startup aborted: Failed to free ports")
            return
        }
        
        // Build config
        addLog("[ClashServiceActor] 📝 Building configuration...")
        do {
            let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
            try await ConfigService.shared.buildConfig(tunEnabled: tunEnabled)
        } catch {
            addLog("[ClashServiceActor] ❌ Config build failed: \(error)")
            return
        }
        
        // Check binary exists
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            addLog("[ClashServiceActor] ❌ Binary not found at: \(binaryPath)")
            return
        }
        
        addLog("[ClashServiceActor] ✅ Binary found: clash-meta")
        
        // Start based on TUN mode
        let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
        
        // Update API controller port immediately
        await MainActor.run {
            ClashController.shared.updatePort(tunEnabled: tunEnabled)
        }
        
        if tunEnabled {
            await startWithTUN()
        } else {
            await startNormal()
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        addLog(String(format: "[ClashServiceActor] ⏱️ Total startup time: %.2fs", endTime - startTime))
    }
    
    /// Stop Clash process
    /// - Parameter intendedRestart: If true, preserves state for hot restart
    func stop(intendedRestart: Bool = false) async {
        addLog("[ClashServiceActor] 🛑 Stopping Clash...")
        
        // Mark as not running immediately
        isRunning = false
        await notifyRunningState(false)
        
        // Terminate tracked process if exists
        if let proc = process, proc.isRunning {
            addLog("[ClashServiceActor] 📍 Terminating tracked process (SIGTERM)...")
            proc.terminate()
            // Wait briefly for SIGTERM to work
            try? await Task.sleep(nanoseconds: 300_000_000)
            if proc.isRunning {
                addLog("[ClashServiceActor] 📍 Tracked process still alive, sending SIGKILL...")
                proc.interrupt() // On macOS process.interrupt often sends SIGINT, and there is no direct SIGKILL via Process
                // We'll fall back to pkill -9 below for a guaranteed kill
            }
        }
        
        if let pid = currentProcessPID {
            addLog("[ClashServiceActor] 📍 Clearing tracked PID: \(pid)")
            currentProcessPID = nil
        }
        
        // Kill all clash-meta processes
        addLog("[ClashServiceActor] 🧹 Starting port-based cleanup...")
        let cleanupSuccess = await performPortCleanup()
        
        if !cleanupSuccess {
            addLog("[ClashServiceActor] ❌ Cleanup failed - ports still busy")
        }
        
        addLog("[ClashServiceActor] ✅ Cleanup completed")
        
        process = nil
        pipe = nil
        
        if !intendedRestart {
            addLog("[ClashServiceActor] ✅ Stopped")
        } else {
            addLog("[ClashServiceActor] ✅ Stopped (preparing for restart)")
        }
    }
    
    // MARK: - Private Methods
    
    private func createConfigDirIfNeeded() async {
        do {
            try await fileManager.createDirectoryIfNeeded(at: configDir)
        } catch {
            logger.error("Failed to create config directory: \(error)")
        }
    }
    
    // Dynamic config directory based on mode to prevent permission conflicts
    private func getConfigDir(tun: Bool) async -> URL {
        return await ConfigService.shared.getConfigDir(tunEnabled: tun)
    }
    
    private func startWithTUN() async {
        let tunConfigDir = await getConfigDir(tun: true)
        
        // Ensure MMDB exists in TUN dir (copy from bundle or user dir if needed)
        // For now, let's assume if it exists in user dir, copy it to TUN dir
        let userConfigDir = await getConfigDir(tun: false)
        let mmdbUserPath = userConfigDir.appendingPathComponent("Country.mmdb").path
        let mmdbTunPath = tunConfigDir.appendingPathComponent("Country.mmdb").path
        
        // Check for bundled MMDB first
        if !FileManager.default.fileExists(atPath: mmdbTunPath) {
            // Check bundled resource
            if let bundledMMDB = Bundle.main.path(forResource: "Country", ofType: "mmdb") {
                 addLog("[ClashServiceActor] 📦 Found bundled MMDB, installing to TUN dir...")
                 try? FileManager.default.copyItem(atPath: bundledMMDB, toPath: mmdbTunPath)
            } else if FileManager.default.fileExists(atPath: mmdbUserPath) {
                 // Fallback: Copy from user dir if exists
                 addLog("[ClashServiceActor] 📦 Mirroring MMDB from User dir...")
                 try? FileManager.default.copyItem(atPath: mmdbUserPath, toPath: mmdbTunPath)
            }
        }
        
        addLog("[ClashServiceActor] 🛡️ TUN mode: Preparing privileged startup...")
        
        let sudoPath = "/usr/bin/sudo"
        
        // Use -d to specify working directory
        let arguments = ["-n", binaryPath, "-d", tunConfigDir.path]
        
        addLog("[ClashServiceActor] Starting with sudo...")
        
        // Use Process directly for non-blocking launch
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sudoPath)
        proc.arguments = arguments
        
        // Pipe output
        let outputPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = outputPipe
        
        do {
            try proc.run()
            process = proc
            pipe = outputPipe
            
            // Drain pipe in background to avoid process freeze
            setupOutputObserver(pipe: outputPipe)
            
            addLog("[ClashServiceActor] ✅ Clash launched with TUN (PID: \(proc.processIdentifier))")
            isRunning = true
            await notifyRunningState(true)
            
            // Background port verification (informational only)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // Increase wait to 1.5s
                let portReady = await waitForPort(19097, timeout: 5.0)
                if !portReady {
                    addLog("[ClashServiceActor] ⚠️ Port 19097 check timeout - core may still be initializing")
                } else {
                    addLog("[ClashServiceActor] 🟢 Port 19097 is now listening")
                }
            }
        } catch {
            addLog("[ClashServiceActor] ❌ TUN start failed: \(error)")
            logger.error("TUN start failed: \(error)")
        }
    }
    
    private func startNormal() async {
        let userConfigDir = await getConfigDir(tun: false)
        
        // Ensure MMDB exists in User dir (copy from TUN dir if needed)
        let tunConfigDir = await getConfigDir(tun: true)
        let mmdbUserPath = userConfigDir.appendingPathComponent("Country.mmdb").path
        let mmdbTunPath = tunConfigDir.appendingPathComponent("Country.mmdb").path
        
        // Check for bundled MMDB first (Normal Mode)
        if !FileManager.default.fileExists(atPath: mmdbUserPath) {
             if let bundledMMDB = Bundle.main.path(forResource: "Country", ofType: "mmdb") {
                  addLog("[ClashServiceActor] 📦 Found bundled MMDB, installing to User dir...")
                  try? FileManager.default.copyItem(atPath: bundledMMDB, toPath: mmdbUserPath)
             } else if FileManager.default.fileExists(atPath: mmdbTunPath) {
                  // Fallback: Copy from TUN dir
                  addLog("[ClashServiceActor] 📦 Mirroring MMDB from TUN dir...")
                  try? FileManager.default.copyItem(atPath: mmdbTunPath, toPath: mmdbUserPath)
             }
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["-d", userConfigDir.path]
        
        let outputPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = outputPipe
        
        do {
            try proc.run()
            process = proc
            pipe = outputPipe
            
            // Drain pipe in background
            setupOutputObserver(pipe: outputPipe)
            
            isRunning = true
            await notifyRunningState(true)
            addLog("[ClashServiceActor] ✅ Clash launched (Normal)")
            logger.info("Clash started successfully")
            
            // Background port verification (informational only)
            Task {
                let portReady = await waitForPort(9097, timeout: 5.0)
                if !portReady {
                    addLog("[ClashServiceActor] ⚠️ Port 9097 check timeout - core may still be initializing")
                }
            }
        } catch {
            addLog("[ClashServiceActor] ❌ Failed to start: \(error)")
            logger.error("Failed to start clash: \(error)")
        }
    }
    
    // Check if a port is open (simple TCP connect)
    private func waitForPort(_ port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().timeIntervalSince1970 + timeout
        while Date().timeIntervalSince1970 < deadline {
            let pids = await processManager.getPIDsUsingPort(port)
            if !pids.isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
        return false
    }
    
    private func cleanupOldProcesses() async -> Bool {
        // Get actual configured ports dynamically
        let defaults = UserDefaults.standard
        let normalMixedPort = Int(defaults.string(forKey: "mixedPort") ?? "7890") ?? 7890
        let normalSocksPort = Int(defaults.string(forKey: "socksPort") ?? "7891") ?? 7891
        let normalHttpPort = Int(defaults.string(forKey: "httpPort") ?? "7892") ?? 7892
        
        // Clean up both Normal and TUN mode ports to be thorough
        let portsToClean = [
            normalMixedPort, normalSocksPort, normalHttpPort, 9097,  // Normal mode
            17890, 17891, 17892, 19097  // TUN mode (fixed)
        ]
        
        var killedAny = false
        
        for port in portsToClean {
            let pids = await processManager.getPIDsUsingPort(port)
            if !pids.isEmpty {
                killedAny = true
                addLog("[ClashServiceActor] ⚠️ Found processes on port \(port): \(pids)")
                for pid in pids {
                    let success = await processManager.killProcess(pid)
                    if !success {
                        addLog("[ClashServiceActor] ⚠️ Failed to kill PID \(pid) (may require sudo)")
                    }
                }
            }
        }
        
        // Also kill by name aggressively
        await processManager.killAllProcesses(matching: "clash-meta")
        
        // Final aggressive sweep with sudo pkill -9
        let aggressiveKill = Process()
        aggressiveKill.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        aggressiveKill.arguments = ["-n", "/usr/bin/pkill", "-9", "-f", "clash-meta"]
        try? aggressiveKill.run()
        aggressiveKill.waitUntilExit()
        
        if killedAny {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s initial wait
        }
        
        // Wait for ports to release (Verified Loop) - Increased to 10s
        let deadline = Date().timeIntervalSince1970 + 10.0
        while Date().timeIntervalSince1970 < deadline {
            var allFreed = true
            for port in portsToClean {
                let pids = await processManager.getPIDsUsingPort(port)
                if !pids.isEmpty {
                    allFreed = false
                    // Retry kill inside loop
                     for pid in pids {
                        _ = await processManager.killProcess(pid)
                    }
                    break
                }
            }
            if allFreed {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s check interval
        }
        
        addLog("[ClashServiceActor] ⚠️ Cleanup timeout: Ports might still be busy")
        // Force kill one last time just in case
        await processManager.killAllProcesses(matching: "clash-meta")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Final check
        for port in portsToClean {
            let pids = await processManager.getPIDsUsingPort(port)
            if !pids.isEmpty {
                addLog("[ClashServiceActor] ❌ Port \(port) still occupied by: \(pids)")
                return false
            }
        }
        return true
    }
    
    private func performPortCleanup() async -> Bool {
        // Get actual configured ports dynamically
        let defaults = UserDefaults.standard
        let normalMixedPort = Int(defaults.string(forKey: "mixedPort") ?? "7890") ?? 7890
        let normalSocksPort = Int(defaults.string(forKey: "socksPort") ?? "7891") ?? 7891
        let normalHttpPort = Int(defaults.string(forKey: "httpPort") ?? "7892") ?? 7892
        
        let portsToCheck = [
            normalMixedPort, normalSocksPort, normalHttpPort, 9097,  // Normal mode
            17890, 17891, 17892, 19097  // TUN mode (fixed)
        ]
        
        // Kill by port
        for port in portsToCheck {
            let pids = await processManager.getPIDsUsingPort(port)
            if !pids.isEmpty {
                addLog("[ClashServiceActor] 🔫 Port \(port) held by PIDs: \(pids) - killing...")
                for pid in pids {
                    _ = await processManager.killProcess(pid)
                }
            }
        }
        
        // Verify ports released
        for attempt in 1...5 { // Reduced from 10
            var busyPorts: [Int] = []
            for port in portsToCheck {
                let pids = await processManager.getPIDsUsingPort(port)
                if !pids.isEmpty {
                    busyPorts.append(port)
                }
            }
            
            if busyPorts.isEmpty {
                // Port cleanup verified
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                return true
            } else {
                addLog("[ClashServiceActor] ⏳ Attempt \(attempt)/5: Busy ports: \(busyPorts)")
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s wait before retry
            }
        }
        
        addLog("[ClashServiceActor] ⚠️ FAILED: Some ports still busy")
        return false
    }
    
    private func getPIDsForClashMeta() async -> [Int32] {
        let output = await processManager.runSimple("/usr/bin/pgrep", args: ["-n", "clash-meta"])
        return output.components(separatedBy: .newlines)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    // MARK: - UI Notification
    
    /// Add log message (non-blocking, updates UI on MainActor)
    nonisolated func addLog(_ message: String) {
        Task { @MainActor in
            ClashViewModel.shared.addLog(message)
        }
    }
    
    /// Notify UI of running state change
    private func notifyRunningState(_ running: Bool) async {
        await MainActor.run {
            ClashViewModel.shared.updateRunningState(running)
        }
    }
    
    private func setupOutputObserver(pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { 
                h.readabilityHandler = nil
                return 
            }
            
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    // Also print to console for easier debugging
                    print("[ClashCore] \(line)")
                    self?.addLog("[Core] \(line)")
                }
            }
        }
    }
}
