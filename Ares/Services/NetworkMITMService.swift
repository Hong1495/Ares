import Foundation
import Combine

/// UI-facing Service for MITM Proxy.
/// Acts as a bridge between SwiftUI (MainActor) and the MITMBackend (Actor).
@MainActor
final class NetworkMITMService: ObservableObject {
    static let shared = NetworkMITMService()
    
    @Published var isRunning = false
    @Published var currentPort: UInt16 = 0
    @Published var interceptedRequests: [InterceptedRequest] = []
    
    private var isSetup = false
    
    private init() {}
    
    private func setupCallbacks() async {
        guard !isSetup else { return }
        isSetup = true
        
        // Await the actor call directly
        await MITMBackend.shared.setCallbacks(
            statusUpdate: { [weak self] isRunning, port in
                Task { @MainActor in
                    self?.updateStatus(isRunning: isRunning, port: port)
                }
            },
            interception: { [weak self] host, method, path in
                Task { @MainActor in
                    self?.recordRequest(host: host, method: method, path: path)
                }
            }
        )
    }
    
    func start() async {
        ClashViewModel.shared.addLog("[NetworkMITMService] 🟢 Starting MITM Service...")
        await setupCallbacks()
        
        // Access shared state safely
        let port = UserDefaults.standard.integer(forKey: "mixedPort") == 0 ? 7890 : UserDefaults.standard.integer(forKey: "mixedPort")
        
        await MITMBackend.shared.start(clashPort: UInt16(port))
        
        // Wait for listener to be ready (up to 2 seconds)
        for i in 0..<20 {
            if isRunning && currentPort > 0 {
                ClashViewModel.shared.addLog("[NetworkMITMService] ✅ MITM Service Ready on port \(currentPort)")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            if i == 19 {
                 ClashViewModel.shared.addLog("[NetworkMITMService] ⚠️ MITM Service startup timed out (isRunning=\(isRunning))")
            }
        }
    }
    
    func stop() async {
        ClashViewModel.shared.addLog("[NetworkMITMService] 🔴 Stopping MITM Service...")
        await MITMBackend.shared.stop()
        
        // Wait for stop to complete
        for _ in 0..<10 {
            if !isRunning {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        ClashViewModel.shared.addLog("[NetworkMITMService] 🛑 MITM Service Stopped")
    }
    
    // Only mutable on MainActor
    private func updateStatus(isRunning: Bool, port: UInt16) {
        ClashViewModel.shared.addLog("[NetworkMITMService] 📊 Status Update: running=\(isRunning), port=\(port)")
        self.isRunning = isRunning
        self.currentPort = port
    }
    
    private func recordRequest(host: String, method: String, path: String) {
        let request = InterceptedRequest(host: host, method: method, path: path, timestamp: Date())
        self.interceptedRequests.append(request)
        if self.interceptedRequests.count > 1000 {
            self.interceptedRequests.removeFirst(self.interceptedRequests.count - 1000)
        }
        
        // Ensure path starts with / for valid URL construction
        let normalizedPath = path.isEmpty || path == "/" ? "/" : (path.hasPrefix("/") ? path : "/\(path)")
        
        let type = method == "CONNECT" ? "CONNECT" : "XHR"
        let browserReq = BrowserRequest(
            id: request.id.uuidString,
            url: "https://\(host)\(normalizedPath)",
            method: method,
            type: type,
            initiator: "MITM Proxy",
            timestamp: request.timestamp,
            status: .active
        )
        BrowserAnalysisService.shared.addRequestToTab(tabId: "mitm_proxy_session", request: browserReq)
    }
}

struct InterceptedRequest: Identifiable {
    let id = UUID()
    let host: String
    let method: String
    let path: String
    let timestamp: Date
}
