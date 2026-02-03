import Foundation
import Network
import Combine

// MARK: - 1. Sendable Data Models (Global Scope)
// Ensure all models are Sendable for Swift 6 high-concurrency mode

struct RequestHit: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let timestamp: Date
    let statusCode: Int?
    let duration: Double?
    var requestBody: String?
    var responseBody: String?

    func asRequest(original: BrowserRequest) -> BrowserRequest {
        var copy = original
        copy.timestamp = self.timestamp
        copy.statusCode = self.statusCode
        copy.duration = self.duration
        if let rb = self.requestBody { copy.requestBody = rb }
        if let sb = self.responseBody { copy.responseBody = sb }
        copy.hits = [] // Prevent recursive "Hit History" inside a Hit Snapshot
        return copy
    }
}

struct BrowserRequest: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let url: String
    let method: String
    let type: String
    let initiator: String? // Added for debugging duplicate sources
    var timestamp: Date
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
    var hits: [RequestHit] = []

    enum RequestStatus: String, Codable, Sendable {
        case pending = "pending"
        case active = "active"
        case success = "success"
        case error = "error"
    }

    enum CodingKeys: String, CodingKey {
        case id, url, method, type, initiator, timestamp, status, statusCode, mimeType, size, duration, remoteAddress, requestHeaders, responseHeaders, requestBody, responseBody, errorMessage, hits, hitCount, lastUpdateTimestamp
    }

    // Custom initializer for programmatic creation
    init(id: String, url: String, method: String, type: String, initiator: String? = nil, timestamp: Date, status: RequestStatus) {
        self.id = id; self.url = url; self.method = method; self.type = type; self.initiator = initiator; self.timestamp = timestamp; self.status = status
        // Record the first hit on initialization
        self.hits = [RequestHit(timestamp: timestamp, statusCode: nil, duration: nil, requestBody: nil, responseBody: nil)]
    }

    // Custom Decodable initializer to handle missing fields from browser extension
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        method = try container.decode(String.self, forKey: .method)
        type = try container.decode(String.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        status = try container.decode(RequestStatus.self, forKey: .status)

        // Optional fields
        initiator = try container.decodeIfPresent(String.self, forKey: .initiator)
        statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        remoteAddress = try container.decodeIfPresent(String.self, forKey: .remoteAddress)
        requestHeaders = try container.decodeIfPresent([String: String].self, forKey: .requestHeaders)
        responseHeaders = try container.decodeIfPresent([String: String].self, forKey: .responseHeaders)
        requestBody = try container.decodeIfPresent(String.self, forKey: .requestBody)
        responseBody = try container.decodeIfPresent(String.self, forKey: .responseBody)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        lastUpdateTimestamp = try container.decodeIfPresent(Date.self, forKey: .lastUpdateTimestamp)

        // New fields with defaults - these won't exist in browser extension JSON
        hitCount = try container.decodeIfPresent(Int.self, forKey: .hitCount) ?? 1
        hits = try container.decodeIfPresent([RequestHit].self, forKey: .hits) ?? []
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
    private static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder throws -> Date in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)

            // Fast Path: ISO8601
            if let d = TelemetryWorker.sharedFormatter.date(from: s) { return d }

            // Slow Path: Fractional Seconds handling
            return TelemetryWorker.sharedFractionalFormatter.date(from: s) ?? Date()
        }
        return decoder
    }()

    private static let sharedFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private static let sharedFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var listener: NWListener?

    init() {}

    func start() {
        // Cancel existing listener if any to prevent port conflicts
        if listener != nil {
            print("[TeleWorker] ⚠️ Stopping existing listener before restart...")
            listener?.cancel()
            listener = nil
            // Small delay to allow port to be released
            Thread.sleep(forTimeInterval: 0.1)
        }

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
            print("[TeleWorker] 🚀 Listener started on port 10086")
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
        if let updates = try? Self.sharedDecoder.decode([PayloadWrapper].self, from: data) {
            // Debug: Log received request methods
            for update in updates {
                if let req = update.request {
                    // Highlight body capture requests
                    if req.id.hasPrefix("body-") {
                        // let hasReqBody = req.requestBody != nil
                        // let hasResBody = req.responseBody != nil
                        // print("[TeleWorker] 📦 BODY CAPTURE: \(req.method) \(req.url.prefix(40))... reqBody:\(hasReqBody) resBody:\(hasResBody)")
                    } else {
                        // print("[TeleWorker] 📥 Received: \(req.method) \(req.url.prefix(60))...")
                    }
                }
            }
            Task { @MainActor in
                BrowserAnalysisService.shared.handleBatchedUpdates(updates)
            }
            return true
        }

        // 2. Try Single (Object)
        if let wrapper = try? Self.sharedDecoder.decode(PayloadWrapper.self, from: data) {
            /*
            if let req = wrapper.request {
                // print("[TeleWorker] 📥 Received: \(req.method) \(req.url.prefix(60))...")
            }
            */
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

    func stop() {
        listener?.cancel()
        listener = nil
        Task { @MainActor in
            BrowserAnalysisService.shared.isListening = false
        }
        print("[TeleWorker] 🛑 Listener stopped")
    }
}

// MARK: - 3. UI Service (Main Actor)

// MARK: - 3. UI Service (Main Actor)

actor BrowserAnalyzer {
    // Internal state for fast lookups
    private var tabMap: [String: BrowserTab] = [:]

    // Config
    private let staleThreshold: TimeInterval = 600 // 10 mins

    func process(activeTabs: [BrowserTab], wrappers: [PayloadWrapper]) -> [BrowserTab] {
        var needsSort = false

        // 1. Sync internal map if needed (first run or reset)
        if tabMap.isEmpty && !activeTabs.isEmpty {
            for tab in activeTabs {
                tabMap[tab.id] = tab
            }
        }

        // 2. Apply Updates
        for w in wrappers {
            if let req = w.request, let tid = w.tabId {
                addRequestToTab(tabId: tid, request: req)
                needsSort = true
            } else if let tab = w.id != nil ? w.asTab() : nil {
                updateTab(tab)
                needsSort = true
            } else if let tid = w.tabId, w.tabRemoved == true {
                removeTab(id: tid)
                needsSort = true
            }
        }

        // 3. Prune Stale
        pruneStaleTabs()

        // 4. Return sorted list (only if needed to save CPU, but usually for UI we sort)
        // For simplicity, we return sorted values
        return tabMap.values.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private func updateTab(_ tab: BrowserTab) {
        if var existing = tabMap[tab.id] {
            existing.url = tab.url
            existing.title = tab.title
            existing.lastUpdate = Date()
            tabMap[tab.id] = existing
        } else {
            tabMap[tab.id] = tab
        }
    }

    func addRequest(tabId: String, request: BrowserRequest) -> [BrowserTab] {
        addRequestToTab(tabId: tabId, request: request)
        pruneStaleTabs()
        return tabMap.values.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private func addRequestToTab(tabId: String, request: BrowserRequest) {
        var tab = tabMap[tabId] ?? BrowserTab(
            id: tabId,
            url: request.url,
            title: "Loading...",
            lastUpdate: Date(),
            requests: []
        )

        // 1. Precise ID Matching
        if let ri = tab.requests.firstIndex(where: { $0.id == request.id }) {
            // print("[BrowserAnalyzer] ✅ Found matching request by ID: \(request.id)")
            merge(request, into: &tab.requests[ri])
        }
        // 2. Heuristic Body Matching
        else if request.id.hasPrefix("body-") {
            let bodyMatchWindow = 5.0
            if let mi = tab.requests.firstIndex(where: {
                guard $0.url == request.url && $0.method == request.method else { return false }
                let refTime = $0.lastUpdateTimestamp ?? $0.timestamp
                return abs(refTime.timeIntervalSince(request.timestamp)) < bodyMatchWindow
            }) {
                merge(request, into: &tab.requests[mi])
            }
        }
        // 3. New Entry or Polling Coalescing
        else {
            var nr = request; nr.lastUpdateTimestamp = Date()
            let isSafeMethod = ["GET", "HEAD", "OPTIONS"].contains(request.method.uppercased())
            let recentThreshold = 0.5

            if isSafeMethod, let ei = tab.requests.firstIndex(where: {
                $0.url == request.url && $0.method == request.method &&
                abs($0.timestamp.timeIntervalSince(request.timestamp)) < recentThreshold
            }) {
                tab.requests[ei].hitCount += 1

                let newHit = RequestHit(
                    timestamp: request.timestamp,
                    statusCode: request.statusCode,
                    duration: request.duration,
                    requestBody: request.requestBody,
                    responseBody: request.responseBody
                )
                tab.requests[ei].hits.append(newHit)

                if tab.requests[ei].hits.count > 50 {
                    tab.requests[ei].hits.removeFirst(tab.requests[ei].hits.count - 50)
                }

                merge(request, into: &tab.requests[ei])
            } else {
                tab.requests.insert(nr, at: 0)
            }
        }

        tab.lastUpdate = Date()

        // History limit
        if tab.requests.count > 500 {
            tab.requests.removeLast()
        }

        tabMap[tabId] = tab
    }

    private func removeTab(id: String) {
        tabMap.removeValue(forKey: id)
    }

    private func pruneStaleTabs() {
        let now = Date()
        let staleKeys = tabMap.filter { now.timeIntervalSince($0.value.lastUpdate) > staleThreshold }.map { $0.key }
        for k in staleKeys { tabMap.removeValue(forKey: k) }
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

        if !dst.hits.isEmpty {
            let lastIdx = dst.hits.count - 1
            var hit = dst.hits[lastIdx]
            if let c = src.statusCode { hit = RequestHit(timestamp: hit.timestamp, statusCode: c, duration: hit.duration, requestBody: hit.requestBody, responseBody: hit.responseBody) }
            if let d = src.duration { hit = RequestHit(timestamp: hit.timestamp, statusCode: hit.statusCode, duration: d, requestBody: hit.requestBody, responseBody: hit.responseBody) }
            if let rb = src.requestBody { hit.requestBody = rb }
            if let sb = src.responseBody { hit.responseBody = sb }
            dst.hits[lastIdx] = hit
        }

        dst.lastUpdateTimestamp = Date()
    }

    func reset() {
        tabMap.removeAll()
    }
}

@MainActor
class BrowserAnalysisService: ObservableObject {
    static let shared = BrowserAnalysisService()

    @Published var activeTabs: [BrowserTab] = []
    @Published var isListening = false
    @Published var lastReceived: Date?
    @Published var connectionCount: Int = 0

    private let worker = TelemetryWorker()
    private let analyzer = BrowserAnalyzer()

    private var pendingWrappers: [PayloadWrapper] = []
    private var isBatching = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        worker.start()

        // MARK: - Global Lifecycle (Event Bus)
        NotificationCenter.default.publisher(for: .appDidGoSilent)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("[BrowserAnalysis] 🌙 Received Silence Signal - HARD STOP")
                self?.stopListening()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appDidWakeUp)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("[BrowserAnalysis] ☀️ Received Wake Signal - RESTART")
                self?.startListening()
            }
            .store(in: &cancellables)
    }

    /// Start listening for browser extension data
    func startListening() {
        guard !isListening else { return }
        worker.start()
    }

    /// Stop listening for browser extension data
    func stopListening() {
        guard isListening else { return }
        worker.stop()
    }

    /// Toggle listening state
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func handleBatchedUpdates(_ wrappers: [PayloadWrapper]) {
        self.pendingWrappers.append(contentsOf: wrappers)

        guard !isBatching else { return }
        isBatching = true

        Task {
            // Buffer updates for 500ms to avoid flooding Main Actor
            try? await Task.sleep(nanoseconds: 500_000_000)

            await self.applyPendingUpdates()
            self.isBatching = false
        }
    }

    private func applyPendingUpdates() async {
        guard !pendingWrappers.isEmpty else { return }

        let wrappers = pendingWrappers
        pendingWrappers.removeAll()

        let count = wrappers.count

        // Offload processing to background Actor
        // We pass the current UI state (activeTabs) to sync the actor if needed, or rely on actor state.
        // To be safe and robust, we pass activeTabs to actor only if actor is empty (handled inside process),
        // or we fully rely on actor state. Let's rely on actor state for integrity.
        let newTabs = await analyzer.process(activeTabs: self.activeTabs, wrappers: wrappers)

        // Update UI
        self.activeTabs = newTabs
        self.lastReceived = Date()
        self.connectionCount += count
    }

    func addRequestToTab(tabId: String, request: BrowserRequest) {
        Task {
            let newTabs = await analyzer.addRequest(tabId: tabId, request: request)
            await MainActor.run {
                self.activeTabs = newTabs
                self.lastReceived = Date()
            }
        }
    }
}

extension BrowserRequest {
    func generateCurl() -> String {
        var curl = "curl '\(self.url)'"
        curl += " \\\n  -X \(self.method.uppercased())"

        if let headers = self.requestHeaders {
            for (k, v) in headers {
                curl += " \\\n  -H '\(k): \(v)'"
            }
        }

        if let body = self.requestBody, !body.isEmpty {
            // Attempt to escape single quotes
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            curl += " \\\n  --data-raw '\(escapedBody)'"
        }

        return curl
    }

    var securityIssues: [String] {
        var issues: [String] = []
        let headers = self.responseHeaders ?? [:]
        let keys = headers.keys.map { $0.lowercased() }

        // CORS
        if !keys.contains("access-control-allow-origin") {
            issues.append("Missing CORS Header (Access-Control-Allow-Origin)")
        }

        // CSP
        if !keys.contains("content-security-policy") {
            issues.append("Missing Content-Security-Policy")
        }

        // HSTS
        if self.url.lowercased().hasPrefix("https") && !keys.contains("strict-transport-security") {
            issues.append("Missing Strict-Transport-Security (HSTS)")
        }

        // X-Content-Type
        if !keys.contains("x-content-type-options") {
            issues.append("Missing X-Content-Type-Options: nosniff")
        }

        return issues
    }

    var performanceInsights: [String] {
        var insights: [String] = []
        if let d = self.duration {
            if d > 1.0 { insights.append("Slow Request (>1s). Consider optimizing backend or caching.") }
            else if d > 0.5 { insights.append("Moderate Latency (>500ms).") }
        }

        // Compression
        let headers = self.responseHeaders ?? [:]
        let encoding = headers.first { $0.key.lowercased() == "content-encoding" }?.value.lowercased()
        if let size = self.size, size > 1024, encoding == nil {
            insights.append("Large response (\(size) bytes) without Content-Encoding (gzip/br).")
        }

        return insights
    }
}
