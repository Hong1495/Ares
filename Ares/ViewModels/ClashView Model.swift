import Foundation
import Combine

/// ViewModel for Clash service - handles UI state only
/// Business logic delegated to ClashService actor
@MainActor
class ClashViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var isRunning: Bool = false
    @Published var logs: [String] = []
    
    // MARK: - Singleton
    static let shared = ClashViewModel()
    
    private init() {}
    
    // MARK: - Public Methods (UI-facing)
    
    func start(isRestart: Bool = false) async {
        // Sync Controller port with App State BEFORE activating monitors
        let tunEnabled = await MainActor.run { AppState.shared.tunEnabled }
        ClashController.shared.updatePort(tunEnabled: tunEnabled)
        
        // Optimistic update - this triggers Controller to start monitors
        DispatchQueue.main.async {
            self.isRunning = true
        }
        
        await ClashServiceActor.shared.start(isRestart: isRestart)
        // If start failed, ClashServiceActor calls updateRunningState(false)
    }
    
    func stop(intendedRestart: Bool = false) async {
        // Optimistic update
        DispatchQueue.main.async {
            self.isRunning = false
        }
        await ClashServiceActor.shared.stop(intendedRestart: intendedRestart)
    }
    
    func restart() async {
        // Stop with intended restart flag
        DispatchQueue.main.async {
            self.isRunning = false
        }
        await ClashServiceActor.shared.stop(intendedRestart: true)
        // Start with restart flag
        DispatchQueue.main.async {
            self.isRunning = true
        }
        await ClashServiceActor.shared.start(isRestart: true)
    }
    
    /// Add log message to UI
    /// - Parameter message: Log message
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .medium
        )
        // Clean message to prevent newlines breaking list layout
        let cleanMessage = message.replacingOccurrences(of: "\n", with: " ")
        let logEntry = "[\(timestamp)] \(cleanMessage)"
        
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
