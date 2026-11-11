import Foundation
import Network
import Combine
import Security

/// MANAGER ACTOR
/// Manages the listener and the list of active connection actors.
actor MITMBackend {
    static let shared = MITMBackend()

    private var upstreamPort: UInt16 = 7890
    private var listener: NWListener?
    private var connections: [UUID: MITMBoundConnection] = [:]

    private var onStatusUpdate: ((Bool, UInt16) -> Void)?
    private var onInterception: ((MITMInterceptedData) -> Void)?
    private var onResponse: ((String, MITMInterceptedData) -> Void)?

    // MARK: - Connection Limits
    private static let maxConnections = 500  // Maximum concurrent connections
    private static let handshakeTimeout: TimeInterval = 5  // 5 seconds for TLS handshake (faster cleanup of stuck connections)
    private static let dataIdleTimeout: TimeInterval = 30  // 30 seconds for data idle (allow slow responses)
    private static let cleanupInterval: UInt64 = 15_000_000_000  // 15 seconds cleanup cycle (more aggressive)
    private var connectionCount = 0  // Track total connections created
    private var cleanupTask: Task<Void, Never>?

    // MARK: - Display Whitelist (filter what shows in UI)
    private var displayWhitelist: [String] = []

    // MARK: - Resilience Mode
    private var ideResilienceMode = false

    // MARK: - Network Monitor (Reset)

    // MARK: - API

    func setCallbacks(
        statusUpdate: @escaping (Bool, UInt16) -> Void,
        interception: @escaping (MITMInterceptedData) -> Void,
        response: @escaping (String, MITMInterceptedData) -> Void
    ) {
        self.onStatusUpdate = statusUpdate
        self.onInterception = interception
        self.onResponse = response
    }

    func start(clashPort: UInt16) async {
        await stop()
        upstreamPort = clashPort

        // Load display whitelist from settings
        refreshDisplayWhitelist()
        refreshResilienceMode()

        // Start periodic cleanup task - runs frequently to catch failed TLS handshakes quickly
        cleanupTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.cleanupInterval)
                guard !Task.isCancelled else { return }
                await self?.cleanupStaleConnections()
            }
        }


        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: .any)

            listener.newConnectionHandler = { [weak self] nwConn in
                Task {
                    await self?.createNewConnection(nwConn)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.handleListenerState(state, listener: listener)
                }
            }

            self.listener = listener
            listener.start(queue: .global())

        } catch {
            updateStatus(running: false, port: 0)
        }
    }

    func stop() async {
        // Cancel cleanup task
        cleanupTask?.cancel()
        cleanupTask = nil

        listener?.cancel()
        listener = nil

        // Stop all connections
        let conns = connections.values
        connections.removeAll()
        connectionCount = 0

        for conn in conns {
            await conn.stop()
        }

        updateStatus(running: false, port: 0)
    }

    // MARK: - Internal

    // Actor-isolated method
    func updateUpstream(port: UInt16) { upstreamPort = port }

    func createNewConnection(_ nwConn: NWConnection) async {
        let clashPort = upstreamPort
        // Reject new connections if at capacity
        let currentCount = connections.count
        if currentCount >= Self.maxConnections {
            nwConn.cancel()
            return
        }

        // Log connection count periodically for monitoring
        connectionCount += 1

        let id = UUID()
        let conn = MITMBoundConnection(id: id, clientConnection: nwConn, clashPort: clashPort, cachedWhitelist: self.displayWhitelist, resilienceEnabled: self.ideResilienceMode)
        connections[id] = conn
        await conn.start()
    }

    func removeConnection(id: UUID) {
        connections.removeValue(forKey: id)
    }

    // MARK: - Cleanup and Monitoring

    private func cleanupStaleConnections() async {
        let staleIds = await withTaskGroup(of: UUID?.self) { group in
            for (id, conn) in connections {
                group.addTask {
                    // Use different timeouts based on connection state
                    let isStale = await conn.isStale(
                        handshakeTimeout: Self.handshakeTimeout,
                        dataIdleTimeout: Self.dataIdleTimeout
                    )
                    return isStale ? id : nil
                }
            }
            var ids: [UUID] = []
            for await id in group {
                if let id = id {
                    ids.append(id)
                }
            }
            return ids
        }

        if !staleIds.isEmpty {
            for id in staleIds {
                if let conn = connections.removeValue(forKey: id) {
                    await conn.stop()
                }
            }
        }
    }

    func getConnectionCount() -> (active: Int, total: Int) {
        return (connections.count, connectionCount)
    }

    func reportInterception(_ data: MITMInterceptedData) async {
        // Filter by display whitelist if configured
        if !displayWhitelist.isEmpty && !MITMDomainMatcher.host(data.host, matches: displayWhitelist) {
            return  // Skip displaying this request
        }
        onInterception?(data)
    }

    func reportResponse(requestId: String, data: MITMInterceptedData) async {
        // Filter by display whitelist if configured
        if !displayWhitelist.isEmpty && !MITMDomainMatcher.host(data.host, matches: displayWhitelist) {
            return  // Skip displaying this response
        }
        onResponse?(requestId, data)
    }

    func refreshResilienceMode() {
        ideResilienceMode = UserDefaults.standard.bool(forKey: DefaultsKeys.ideResilienceMode)
    }

    func refreshDisplayWhitelist() {
        let mitmHostsString = UserDefaults.standard.string(forKey: DefaultsKeys.mitmHosts) ?? ""
        displayWhitelist = MITMDomainMatcher.normalizedPatterns(from: mitmHostsString)
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
        guard self.listener === listener else { return }
        switch state {
        case .ready:
            let port = listener.port?.rawValue ?? 0
            updateStatus(running: true, port: port)
        case .failed, .cancelled:
            updateStatus(running: false, port: 0)
        default: break
        }
    }

    private func updateStatus(running: Bool, port: UInt16) {
        onStatusUpdate?(running, port)
    }

    nonisolated static func parseRequest(_ data: Data) -> (method: String, path: String, headers: [String: String], bodyOffset: Int)? {
        HTTPParser.parseRequest(data)
    }

    nonisolated static func parseResponse(_ data: Data) -> (statusCode: Int, headers: [String: String], bodyOffset: Int)? {
        HTTPParser.parseResponse(data)
    }

    nonisolated static func isTextContent(_ contentType: String?) -> Bool {
        HTTPParser.isTextContent(contentType)
    }

    nonisolated static var maxBodyCapture: Int {
        HTTPParser.maxBodyCapture
    }

    nonisolated static func decodeChunkedBody(_ data: Data) -> Data? {
        HTTPParser.decodeChunkedBody(data)
    }

    nonisolated static func decompressGzip(_ data: Data) -> Data? {
        HTTPParser.decompressGzip(data)
    }

    nonisolated static func decompressBrotli(_ data: Data) -> Data? {
        HTTPParser.decompressBrotli(data)
    }
}
