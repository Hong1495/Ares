import Foundation
import Network
import Combine

// MARK: - 1. Sendable Data Models (Global Scope)
// Ensure all models are Sendable for Swift 6 high-concurrency mode

struct BrowserRequest: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let url: String
    let method: String
    let type: String
    let timestamp: Date
    var status: RequestStatus
    var statusCode: Int?
    var mimeType: String?
    var size: Int?
    var duration: Double?
    var remoteAddress: String?
    var requestHeaders: [String: String]?
    var responseHeaders: [String: String]?
    var lastUpdateTimestamp: Date?
    var hitCount: Int = 1
    var requestBody: String?
    var responseBody: String?
    var errorMessage: String?
    
    enum RequestStatus: String, Codable, Sendable {
        case pending = "pending"
        case active = "active"
        case success = "success"
        case error = "error"
    }

    enum CodingKeys: String, CodingKey {
        case id, url, method, type, timestamp, status, statusCode, mimeType, size, duration, remoteAddress, requestHeaders, responseHeaders, requestBody, responseBody, errorMessage
    }

    init(id: String, url: String, method: String, type: String, timestamp: Date, status: RequestStatus) {
        self.id = id; self.url = url; self.method = method; self.type = type; self.timestamp = timestamp; self.status = status
    }

    var sortSize: Int { displaySize }
    var sortDuration: Double { duration ?? 0.0 }
    var sortStatus: String { status.rawValue }
    
    /// Calculate display size from either header or body content
    var displaySize: Int {
        if let s = size, s > 0 { return s }
        // Fallback: estimate size from captured body (common in chunked encoding)
        return (requestBody?.count ?? 0) + (responseBody?.count ?? 0)
    }

    static func == (lhs: BrowserRequest, rhs: BrowserRequest) -> Bool {
        lhs.id == rhs.id && 
        lhs.status == rhs.status && 
        lhs.hitCount == rhs.hitCount && 
        lhs.lastUpdateTimestamp == rhs.lastUpdateTimestamp &&
        (lhs.requestBody != nil) == (rhs.requestBody != nil) &&
        (lhs.responseBody != nil) == (rhs.responseBody != nil)
    }
}

struct BrowserTab: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var url: String
    var title: String
    var lastUpdate: Date
    var requests: [BrowserRequest] = []
    
    static func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url && lhs.title == rhs.title && lhs.lastUpdate == rhs.lastUpdate && lhs.requests == rhs.requests
    }
}

struct PayloadWrapper: Codable, Sendable {
    let tabId: String?
    let request: BrowserRequest?
    let tabRemoved: Bool?
    let id: String?
    let url: String?
    let title: String?
    let lastUpdate: Date?
    let requests: [BrowserRequest]?

    func asTab() -> BrowserTab? {
        guard let id = id, let url = url, let title = title, let lastUpdate = lastUpdate else { return nil }
        return BrowserTab(id: id, url: url, title: title, lastUpdate: lastUpdate, requests: requests ?? [])
    }
}

// MARK: - 2. Background Networking (Global Scope)

/// Robust state management for a single connection
final class ConnectionBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    let connection: NWConnection

    init(connection: NWConnection) { self.connection = connection }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    /// Extract JSON payload if start markers are found
    func getPayload() -> Data? {
        lock.lock(); defer { lock.unlock() }
        if let index = data.firstIndex(of: 0x5B) ?? data.firstIndex(of: 0x7B) {
            return data[index...]
        }
        return nil
    }
    
    func peek(_ limit: Int) -> Data {
        lock.lock(); defer { lock.unlock() }
        return data.prefix(limit)
    }
    
    var size: Int {
        lock.lock(); defer { lock.unlock() }
        return data.count
    }
}

final class TelemetryWorker: @unchecked Sendable {
    private let decoder: JSONDecoder
    private var listener: NWListener?

    init() {
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder throws -> Date in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            let f = ISO8601DateFormatter()
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? Date()
        }
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: 10086)
            
            listener?.stateUpdateHandler = { state in
                Task { @MainActor in
                    BrowserAnalysisService.shared.isListening = (state == .ready)
                }
                print("[TeleWorker] 📡 State: \(state)")
            }
            
            listener?.newConnectionHandler = { [weak self] conn in
                guard let self = self else { return }
                let buffer = ConnectionBuffer(connection: conn)
                conn.start(queue: .global(qos: .userInteractive))
                self.receive(buffer)
            }
            
            listener?.start(queue: .global(qos: .utility))
        } catch {
            print("[TeleWorker] ❌ Failed to start listener: \(error)")
        }
    }

    private func receive(_ buffer: ConnectionBuffer) {
        // High performance receive: max 512KB per chunk
        buffer.connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 512) { [weak self] data, _, isComplete, err in
            guard let self = self else { return }
            
            if let data = data {
                buffer.append(data)
                
                // 1. Detect and handle HTTP Preflight (OPTIONS) or PNA checks
                // We check the first few bytes for the OPTIONS method
                if let payloadStr = String(data: buffer.peek(32), encoding: .utf8), payloadStr.hasPrefix("OPTIONS") {
                    self.sendPreflightResponse(buffer.connection)
                    return
                }
                
                // 2. Attempt to process JSON IMMEDIATELY (Deadlock Avoidance)
                if let payload = buffer.getPayload(), self.process(payload) {
                    self.sendACK(buffer.connection)
                    return // Connection handled
                }
            }

            if err != nil {
                buffer.connection.cancel()
            } else if isComplete {
                if let payload = buffer.getPayload() {
                    self.process(payload)
                }
                buffer.connection.cancel()
            } else {
                self.receive(buffer)
            }
        }
    }

    @discardableResult
    private func process(_ data: Data) -> Bool {
        // Attempt to find the end of the JSON object/array
        // to avoid partial decoding attempts on very large streams
        guard data.count > 2 else { return false }
        
        // 1. Try Batched (Array)
        if let updates = try? decoder.decode([PayloadWrapper].self, from: data) {
            Task { @MainActor in
                BrowserAnalysisService.shared.handleBatchedUpdates(updates)
            }
            return true
        }
        
        // 2. Try Single (Object)
        if let wrapper = try? decoder.decode(PayloadWrapper.self, from: data) {
            Task { @MainActor in
                BrowserAnalysisService.shared.handleBatchedUpdates([wrapper])
            }
            return true
        }
        
        return false // Data not yet complete or malformed
    }

    private func logFailure(_ data: Data) {
        if let s = String(data: data, encoding: .utf8) {
            print("[TeleWorker] ❌ Decoding failed. Snippet: \(s.prefix(200))")
        }
    }

    private func sendACK(_ conn: NWConnection) {
        let ack = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 0\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Private-Network: true\r\nConnection: close\r\n\r\n"
        conn.send(content: ack.data(using: .utf8), completion: .contentProcessed({ _ in 
            conn.cancel() 
        }))
    }
    
    private func sendPreflightResponse(_ conn: NWConnection) {
        let resp = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\nConnection: close\r\n\r\n"
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in 
            conn.cancel() 
        }))
    }
}

// MARK: - 3. UI Service (Main Actor)

@MainActor
class BrowserAnalysisService: ObservableObject {
    static let shared = BrowserAnalysisService()
    
    @Published var activeTabs: [BrowserTab] = []
    @Published var isListening = false
    @Published var lastReceived: Date?
    @Published var connectionCount: Int = 0
    
    private let worker = TelemetryWorker()
    private var pruningTimer: AnyCancellable?
    private let staleThreshold: TimeInterval = 600 // Keep tabs for 10 mins without updates
    
    private init() {
        worker.start()
        startPruningTimer()
    }

    func handleBatchedUpdates(_ wrappers: [PayloadWrapper]) {
        self.lastReceived = Date()
        self.connectionCount += wrappers.count
        
        // Batch updates to reduce View redraws
        objectWillChange.send()
        
        for w in wrappers {
            if let req = w.request, let tid = w.tabId {
                addRequestToTab(tabId: tid, request: req)
            } else if let tab = w.id != nil ? w.asTab() : nil {
                updateTab(tab)
            } else if let tid = w.tabId, w.tabRemoved == true {
                removeTab(id: tid)
            }
        }
    }
    
    private func updateTab(_ tab: BrowserTab) {
        if let i = activeTabs.firstIndex(where: { $0.id == tab.id }) {
            activeTabs[i].url = tab.url
            activeTabs[i].title = tab.title
            activeTabs[i].lastUpdate = Date()
        } else {
            activeTabs.append(tab)
        }
    }
    
    func addRequestToTab(tabId: String, request: BrowserRequest) {
        if let i = activeTabs.firstIndex(where: { $0.id == tabId }) {
            addRequestToTabIndex(i, request: request)
        } else {
            // Race condition: request arrived before tab metadata. Create placeholder.
            activeTabs.append(BrowserTab(
                id: tabId, 
                url: request.url, 
                title: "Loading...", 
                lastUpdate: Date(), 
                requests: [request]
            ))
        }
    }
    
    private func addRequestToTabIndex(_ i: Int, request: BrowserRequest) {
        // 1. Precise ID Matching (Internal tracking)
        if let ri = activeTabs[i].requests.firstIndex(where: { $0.id == request.id }) {
            merge(request, into: &activeTabs[i].requests[ri])
        } 
        // 2. Heuristic Body Matching (IDs starting with "body-")
        else if request.id.hasPrefix("body-"),
                let mi = activeTabs[i].requests.lastIndex(where: {
                    $0.url == request.url && $0.method == request.method && 
                    abs($0.timestamp.timeIntervalSince(request.timestamp)) < 15.0 // More generous window for bodies
                }) {
            merge(request, into: &activeTabs[i].requests[mi])
        } 
        // 3. New Entry or Polling Coalescing
        else {
            var nr = request; nr.lastUpdateTimestamp = Date()
            
            // Smart polling merge: If the same request appears within 5s, increment hitCount
            let recentThreshold = 5.0
            if let ei = activeTabs[i].requests.firstIndex(where: {
                $0.url == request.url && $0.method == request.method && 
                abs($0.timestamp.timeIntervalSince(request.timestamp)) < recentThreshold
            }) {
                activeTabs[i].requests[ei].hitCount += 1
                activeTabs[i].requests[ei].lastUpdateTimestamp = Date()
                activeTabs[i].requests[ei].status = request.status
                // Merge status/codes if updated
                if request.statusCode != nil { activeTabs[i].requests[ei].statusCode = request.statusCode }
            } else {
                activeTabs[i].requests.insert(nr, at: 0)
            }
        }
        
        activeTabs[i].lastUpdate = Date()
        
        // History limit: keep it under 500 items per tab
        if activeTabs[i].requests.count > 500 {
            activeTabs[i].requests.removeLast()
        }
    }
    
    private func removeTab(id: String) {
        activeTabs.removeAll(where: { $0.id == id })
    }
    
    private func startPruningTimer() {
        pruningTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pruneStaleTabs()
            }
    }
    
    private func pruneStaleTabs() {
        let now = Date()
        activeTabs.removeAll { now.timeIntervalSince($0.lastUpdate) > staleThreshold }
    }
    
    private func merge(_ src: BrowserRequest, into dst: inout BrowserRequest) {
        if src.status != .pending { dst.status = src.status }
        if let c = src.statusCode { dst.statusCode = c }
        if let m = src.mimeType { dst.mimeType = m }
        if let s = src.size, s > 0 { dst.size = s }
        if let d = src.duration, d > 0 { dst.duration = d }
        if let ip = src.remoteAddress { dst.remoteAddress = ip }
        if let reqH = src.requestHeaders { dst.requestHeaders = reqH }
        if let resH = src.responseHeaders { dst.responseHeaders = resH }
        if let reqB = src.requestBody { dst.requestBody = reqB }
        if let resB = src.responseBody { dst.responseBody = resB }
        if let msg = src.errorMessage { dst.errorMessage = msg }
        dst.lastUpdateTimestamp = Date()
    }
}
