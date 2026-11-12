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
    private let processReaper = CoreProcessReaper()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.ares", category: "ClashServiceActor")
    
    // MARK: - State (Private, Actor-Isolated)
    private var isRunning: Bool = false
    private var process: Process?
    private var pipe: Pipe?
    private var lifecycleBusy = false
    
    // MARK: - Configuration
    private var configDir: URL {
        Self.applicationSupportDirectory()
            .appendingPathComponent("Ares")
            .appendingPathComponent("clash")
    }
    
    private var binaryPath: String {
        get async {
            await CoreManager.shared.activeBinaryPath()
        }
    }
    
    // MARK: - Initialization
    private init() {
        Task {
            await createConfigDirIfNeeded()
        }
    }

    private static func applicationSupportDirectory() -> URL {
        if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }
    
    // MARK: - Public Methods
    
    /// Start Clash process
    /// - Parameter isRestart: If true, bypasses "already running" check
    func start(isRestart: Bool = false) async -> Bool {
        guard !lifecycleBusy else { return false }
        lifecycleBusy = true
        defer { lifecycleBusy = false }
        let startTime = CFAbsoluteTimeGetCurrent()
        addLog("[ClashServiceActor] 🚀 Starting Clash...")
        
        // Check if already running
        if process?.isRunning == true {
            addLog("[ClashServiceActor] ⚠️ Already running")
            return !isRestart
        }
        
        isRunning = false
        // Reclaim Ares-owned children left by a crash, update or older build first.
        do {
            if try await !processReaper.ownedProcesses().isEmpty {
                let restored = await MainActor.run { SystemProxyManager.shared.disableAllProxiesSync() }
                guard restored else {
                    await MainActor.run { ClashViewModel.shared.markStartFailed("Restore the previous Ares system proxy before recovering its core.") }
                    return false
                }
            }
        } catch {
            await MainActor.run { ClashViewModel.shared.markStartFailed("Could not inspect previous Ares processes.") }
            return false
        }
        guard await processReaper.reap() else {
            await MainActor.run { ClashViewModel.shared.markStartFailed("Could not stop a previous Ares core. Authorize cleanup and try again.") }
            return false
        }
        // Only unrelated listeners may remain now.
        addLog("[ClashServiceActor] Checking required ports...")
        let cleanupSuccess = await cleanupOldProcesses()
        if !cleanupSuccess {
            addLog("[ClashServiceActor] ❌ Startup aborted: Required ports are occupied")
            return false
        }
        
        // Build config
        addLog("[ClashServiceActor] 📝 Building configuration...")
        do {
            let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
            try await ConfigService.shared.buildConfig(tunEnabled: tunEnabled)
        } catch {
            addLog("[ClashServiceActor] ❌ Config build failed: \(error)")
            await MainActor.run {
                ClashViewModel.shared.markStartFailed(error.localizedDescription)
            }
            return false
        }
        
        // Check binary exists
        let activeBinaryPath = await binaryPath
        guard FileManager.default.fileExists(atPath: activeBinaryPath) else {
            addLog("[ClashServiceActor] ❌ Binary not found at: \(activeBinaryPath)")
            await MainActor.run {
                ClashViewModel.shared.markStartFailed("Core binary missing")
            }
            return false
        }
        
        addLog("[ClashServiceActor] ✅ Binary found: clash-meta")
        
        // Start based on TUN mode
        let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
        
        // Update API controller port immediately
        await MainActor.run {
            ClashController.shared.updatePort(tunEnabled: tunEnabled)
        }
        
        if tunEnabled {
            // Ensure permissions for TUN mode
            // This is critical for restart/profile switch flows where the outer UI toggle check isn't run
            let hasPrivileges = await PrivilegeService.shared.checkPrivileges()
            if !hasPrivileges {
                addLog("[ClashServiceActor] 🛡️ TUN permissions missing, attempting install...")
                // Note: installSudoers might trigger UI prompt, which is fine
                let installed = await PrivilegeService.shared.installSudoers()
                if !installed {
                     addLog("[ClashServiceActor] ❌ Failed to acquire TUN privileges. Fallback to Normal mode?")
                     return false
                }
            }
            let started = await startWithTUN()
            let endTime = CFAbsoluteTimeGetCurrent()
            addLog(String(format: "[ClashServiceActor] ⏱️ Total startup time: %.2fs", endTime - startTime))
            return started
        } else {
            let started = await startNormal()
            let endTime = CFAbsoluteTimeGetCurrent()
            addLog(String(format: "[ClashServiceActor] ⏱️ Total startup time: %.2fs", endTime - startTime))
            return started
        }
    }
    
    /// Stop Clash process
    /// - Parameter intendedRestart: If true, preserves state for hot restart
    @discardableResult
    func stop(intendedRestart: Bool = false) async -> Bool {
        guard !lifecycleBusy else { return false }
        lifecycleBusy = true
        defer { lifecycleBusy = false }
        // Includes sudo wrappers and children from earlier app launches.
        guard await processReaper.reap() else {
            addLog("[Core] Stop failed: Ares-owned processes remain; restart cancelled")
            return false
        }
        if let proc = process, proc.isRunning {
            proc.terminate()
            for _ in 0..<20 {
                if !proc.isRunning { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !proc.isRunning else { return false }
        }
        process = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        isRunning = false
        return true
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
    
    private func startWithTUN() async -> Bool {
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
        let activeBinaryPath = await binaryPath
        let arguments = ["-n", activeBinaryPath, "-d", tunConfigDir.path]
        
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
            await MainActor.run {
                ClashViewModel.shared.markProcessLaunched()
            }
            
            // Background port verification (informational only)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // Increase wait to 1.5s
                let portReady = await waitForPort(ClashPorts.apiTun, timeout: 5.0)
                if !portReady {
                    addLog("[ClashServiceActor] ⚠️ Port \(ClashPorts.apiTun) check timeout - core may still be initializing")
                } else {
                    addLog("[ClashServiceActor] 🟢 Port \(ClashPorts.apiTun) is now listening")
                }
            }
            return true
        } catch {
            addLog("[ClashServiceActor] ❌ TUN start failed: \(error)")
            logger.error("TUN start failed: \(error)")
            await MainActor.run {
                ClashViewModel.shared.markStartFailed("TUN start failed")
            }
            return false
        }
    }
    
    private func startNormal() async -> Bool {
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
        let activeBinaryPath = await binaryPath
        proc.executableURL = URL(fileURLWithPath: activeBinaryPath)
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
            await MainActor.run {
                ClashViewModel.shared.markProcessLaunched()
            }
            addLog("[ClashServiceActor] ✅ Clash launched (Normal)")
            logger.info("Clash started successfully")
            
            // Background port verification (informational only)
            Task {
                let portReady = await waitForPort(ClashPorts.apiNormal, timeout: 5.0)
                if !portReady {
                    addLog("[ClashServiceActor] ⚠️ Port \(ClashPorts.apiNormal) check timeout - core may still be initializing")
                }
            }
            return true
        } catch {
            addLog("[ClashServiceActor] ❌ Failed to start: \(error)")
            logger.error("Failed to start clash: \(error)")
            await MainActor.run {
                ClashViewModel.shared.markStartFailed("Core start failed")
            }
            return false
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
        let tun = await MainActor.run { AppState.shared.tunEnabled }
        let defaults = UserDefaults.standard
        let ports = tun ? [ClashPorts.tunMixed, ClashPorts.tunSocks, ClashPorts.tunHttp, ClashPorts.apiTun] : [
            Int(defaults.string(forKey: DefaultsKeys.mixedPort) ?? "") ?? ClashPorts.defaultMixed,
            Int(defaults.string(forKey: DefaultsKeys.socksPort) ?? "") ?? ClashPorts.defaultSocks,
            Int(defaults.string(forKey: DefaultsKeys.httpPort) ?? "") ?? ClashPorts.defaultHttp,
            ClashPorts.apiNormal
        ]
        for port in Set(ports) where port > 0 {
            let pids = await processManager.getPIDsUsingPort(port)
            if !pids.isEmpty {
                addLog("[Core] Port \(port) is occupied by \(pids). No process was stopped.")
                await MainActor.run { ClashViewModel.shared.markStartFailed("Port \(port) is already in use") }
                return false
            }
        }
        return true
    }

    // MARK: - UI Notification
    
    /// Add log message (non-blocking, updates UI on MainActor)
    nonisolated func addLog(_ message: String) {
        Task { @MainActor in
            ClashViewModel.shared.addLog(message)
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
                    self?.addLog("[Core] \(line)")
                }
            }
        }
    }
}
