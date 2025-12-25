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
            interception: { [weak self] data in
                Task { @MainActor in
                    self?.recordRequest(data)
                }
            },
            response: { [weak self] requestId, data in
                Task { @MainActor in
                    self?.updateRequestWithResponse(requestId: requestId, data: data)
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
    
    private func recordRequest(_ data: MITMInterceptedData) {
        // Skip CONNECT method for now (just establishes tunnel)
        guard data.method != "CONNECT" else { return }
        
        let request = InterceptedRequest(host: data.host, method: data.method, path: data.path, timestamp: data.timestamp)
        self.interceptedRequests.append(request)
        if self.interceptedRequests.count > 1000 {
            self.interceptedRequests.removeFirst(self.interceptedRequests.count - 1000)
        }
        
        // Determine resource type based on Accept header or path
        let type: String
        if let acceptHeader = data.requestHeaders?.first(where: { $0.key.lowercased() == "accept" })?.value.lowercased() {
            if acceptHeader.contains("json") {
                type = "Fetch"
            } else if acceptHeader.contains("html") {
                type = "Document"
            } else if acceptHeader.contains("image") {
                type = "Image"
            } else if acceptHeader.contains("css") {
                type = "Stylesheet"
            } else if acceptHeader.contains("javascript") {
                type = "Script"
            } else {
                type = "XHR"
            }
        } else {
            type = "XHR"
        }
        
        // Create rich BrowserRequest with full HTTP data
        var browserReq = BrowserRequest(
            id: data.id,
            url: data.url,
            method: data.method,
            type: type,
            initiator: "MITM Proxy",
            timestamp: data.timestamp,
            status: .pending
        )
        
        // Populate request headers
        browserReq.requestHeaders = data.requestHeaders
        browserReq.size = data.requestSize
        
        // Populate request body if captured
        if let bodyData = data.requestBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            browserReq.requestBody = bodyString
        }
        
        BrowserAnalysisService.shared.addRequestToTab(tabId: "mitm_proxy_session", request: browserReq)
    }
    
    private func updateRequestWithResponse(requestId: String, data: MITMInterceptedData) {
        print("[NetworkMITMService] 📥 Updating request \(requestId) with response data")
        
        // Create an update request with response data
        var updateReq = BrowserRequest(
            id: requestId,
            url: "",  // Will be ignored in merge
            method: "RESPONSE",
            type: "XHR",
            initiator: nil,
            timestamp: Date(),
            status: data.statusCode.map { $0 >= 400 ? .error : .success } ?? .success
        )
        
        updateReq.statusCode = data.statusCode
        updateReq.responseHeaders = data.responseHeaders
        updateReq.duration = data.duration
        updateReq.size = data.responseSize
        
        // Populate response body if captured
        if let bodyData = data.responseBody {
            print("[NetworkMITMService] 📦 Response body data: \(bodyData.count) bytes")
            if let bodyString = String(data: bodyData, encoding: .utf8) {
                updateReq.responseBody = bodyString
                print("[NetworkMITMService] ✅ Response body converted to string: \(bodyString.prefix(80))...")
            } else {
                print("[NetworkMITMService] ❌ Failed to convert response body to UTF-8 string")
            }
        } else {
            print("[NetworkMITMService] ⚠️ No response body data in MITMInterceptedData")
        }
        
        // Determine MIME type from response headers
        if let contentType = data.responseHeaders?.first(where: { $0.key.lowercased() == "content-type" })?.value {
            updateReq.mimeType = contentType
        }
        
        print("[NetworkMITMService] 📤 Sending update with responseBody=\(updateReq.responseBody != nil ? "SET(\(updateReq.responseBody!.count) chars)" : "nil")")
        BrowserAnalysisService.shared.addRequestToTab(tabId: "mitm_proxy_session", request: updateReq)
    }
}

struct InterceptedRequest: Identifiable {
    let id = UUID()
    let host: String
    let method: String
    let path: String
    let timestamp: Date
}

