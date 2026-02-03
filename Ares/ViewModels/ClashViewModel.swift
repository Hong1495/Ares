import Foundation
import Combine

/// ViewModel for Clash service - handles UI state only
/// Business logic delegated to ClashService actor
@MainActor
class ClashViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var isRunning: Bool = false
    @Published var logs: [String] = []
    @Published var isToggling: Bool = false
    
    // MARK: - Singleton
    static let shared = ClashViewModel()
    
    private init() {}
    
    // MARK: - Public Methods (UI-facing)
    
    func start(isRestart: Bool = false) async {
        guard !isToggling else { return }
        isToggling = true
        defer { isToggling = false }
        await startCore(isRestart: isRestart)
    }
    
    func stop(intendedRestart: Bool = false) async {
        guard !isToggling else { return }
        isToggling = true
        defer { isToggling = false }
        await stopCore(intendedRestart: intendedRestart)
    }
    
    /// Internal methods for core operations - NO GATING
    func startCore(isRestart: Bool = false) async {
        // Sync Controller port with App State BEFORE activating monitors
        let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
        ClashController.shared.updatePort(tunEnabled: tunEnabled)
        
        self.isRunning = true
        await ClashServiceActor.shared.start(isRestart: isRestart)
    }
    
    func stopCore(intendedRestart: Bool = false) async {
        self.isRunning = false
        await ClashServiceActor.shared.stop(intendedRestart: intendedRestart)
    }
    
    func restart() async {
        // Global operation gate
        guard !isToggling else { return }
        isToggling = true
        defer { isToggling = false }
        
        await stopCore(intendedRestart: true)
        await startCore(isRestart: true)
    }
    
    /// Log levels matching Clash core levels
    enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case silent = 4
        
        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        static func from(string: String) -> LogLevel {
            switch string.lowercased() {
            case "debug": return .debug
            case "info": return .info
            case "warning": return .warning
            case "error": return .error
            case "silent": return .silent
            default: return .info
            }
        }
    }
    
    /// Add log message to UI with level filtering
    /// - Parameters:
    ///   - message: Log message
    ///   - level: Log level (default: .info)
    func addLog(_ message: String, level: LogLevel = .info) {
        // Get user's log level setting
        let userLogLevelString = UserDefaults.standard.string(forKey: DefaultsKeys.logLevel) ?? "info"
        let userLogLevel = LogLevel.from(string: userLogLevelString)
        
        // Filter: only show logs at or above user's level
        guard level >= userLogLevel else { return }
        
        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .medium
        )
        // Clean message to prevent newlines breaking list layout
        let cleanMessage = message.replacingOccurrences(of: "\n", with: " ")
        let logEntry = "[\(timestamp)] \(cleanMessage)"
        
        // Also print to console for debugging
        print(logEntry)
        
        DispatchQueue.main.async {
            self.logs.append(logEntry)
            
            // Efficiently limit to last 1000 lines
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
            }
        }
    }
    
    /// Clear all logs
    func clearLogs() {
        logs = []
    }
    
    /// Update running state from service
    /// - Parameter running: New running state
    func updateRunningState(_ running: Bool) {
        DispatchQueue.main.async {
            self.isRunning = running
        }
    }
}
