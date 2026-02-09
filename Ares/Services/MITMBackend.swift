import Foundation
import Network
import Combine
import Security

/// MANAGER ACTOR
/// Manages the listener and the list of active connection actors.
actor MITMBackend {
    static let shared = MITMBackend()

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

        // Load display whitelist from settings
        refreshDisplayWhitelist()
        refreshResilienceMode()

        // Start periodic cleanup task - runs frequently to catch failed TLS handshakes quickly
        cleanupTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.cleanupInterval)
                await self?.cleanupStaleConnections()
            }
        }


        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: .any)

            listener.newConnectionHandler = { [weak self] nwConn in
                Task {
                    await self?.createNewConnection(nwConn, clashPort: clashPort)
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
    func createNewConnection(_ nwConn: NWConnection, clashPort: UInt16) async {
        // Reject new connections if at capacity
        let currentCount = connections.count
        if currentCount >= Self.maxConnections {
            print("[MITMBackend] ⚠️ Connection limit reached (\(currentCount)/\(Self.maxConnections)), rejecting new connection")
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
            print("[MITMBackend] 🧹 Cleaning up \(staleIds.count) stale connections (active: \(connections.count - staleIds.count))")
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
        if !displayWhitelist.isEmpty {
            let hostLower = data.host.lowercased()
            var shouldDisplay = false
            for pattern in displayWhitelist {
                if hostLower == pattern || hostLower.hasSuffix("." + pattern) {
                    shouldDisplay = true
                    break
                }
                if pattern.hasPrefix("*") {
                    let suffix = String(pattern.dropFirst())
                    if hostLower.hasSuffix(suffix) {
                        shouldDisplay = true
                        break
                    }
                }
            }
            if !shouldDisplay {
                return  // Skip displaying this request
            }
        }
        onInterception?(data)
    }

    func reportResponse(requestId: String, data: MITMInterceptedData) async {
        // Filter by display whitelist if configured
        if !displayWhitelist.isEmpty {
            let hostLower = data.host.lowercased()
            var shouldDisplay = false
            for pattern in displayWhitelist {
                if hostLower == pattern || hostLower.hasSuffix("." + pattern) {
                    shouldDisplay = true
                    break
                }
                if pattern.hasPrefix("*") {
                    let suffix = String(pattern.dropFirst())
                    if hostLower.hasSuffix(suffix) {
                        shouldDisplay = true
                        break
                    }
                }
            }
            if !shouldDisplay {
                return  // Skip displaying this response
            }
        }
        onResponse?(requestId, data)
    }

    func refreshResilienceMode() {
        ideResilienceMode = UserDefaults.standard.bool(forKey: DefaultsKeys.ideResilienceMode)
        print("[MITMBackend] 🛡️ Resilience Mode: \(ideResilienceMode)")
    }

    func refreshDisplayWhitelist() {
        let mitmHostsString = UserDefaults.standard.string(forKey: DefaultsKeys.mitmHosts) ?? ""
        let trimmed = mitmHostsString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            displayWhitelist = []
        } else {
            let separators = CharacterSet(charactersIn: ",，\n")
            displayWhitelist = trimmed.components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            print("[MITMBackend] 📋 Display whitelist: \(displayWhitelist)")
        }
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
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
}

/// WORKER ACTOR
actor MITMBoundConnection: Identifiable {
    nonisolated let id = UUID()
    private let clientConnection: NWConnection
    private let clashPort: UInt16

    private var serverConnection: NWConnection?
    private var loopbackListener: NWListener?
    private var loopbackConnection: NWConnection?      // Track loopback connection
    private var decryptedConnection: NWConnection?     // Track decrypted TLS connection
    private var upstreamConnection: NWConnection?      // Track upstream TLS connection
    private var buffer = Data()
    private var targetHost: String = ""
    private var targetPort: NWEndpoint.Port = 80
    private var isStopped = false  // CRITICAL: Prevent recursive stop calls
    private var isPiping = false   // CRITICAL: Prevent conflicting reads during pipe handover

    // MARK: - Connection Lifecycle Tracking
    private let createdAt = Date()
    private var lastActivity = Date()
    private var handshakeComplete = false  // Track if we've successfully established the pipe

    // Cached whitelist - read once at init to avoid thread issues
    private let cachedWhitelist: [String]

    // Resilience Mode
    private let resilienceEnabled: Bool

    // Request Cache for Retry
    private var cachedRequest: Data?
    private var isRetrying = false
    private var retryCount = 0
    private static let maxRetries = 3

    // Pipe State (Maintained on actor to allow refactoring closures)
    private var firstRequestReported = false
    private var currentRequestId: String?
    private var firstResponseReported = false
    private var requestStartTime = Date()
    private var responseAccumulator = Data()
    private var dataToSendOnRetry: Data?

    func isStale(handshakeTimeout: TimeInterval, dataIdleTimeout: TimeInterval) -> Bool {
        // Already stopped - definitely stale
        if isStopped { return true }

        let age = Date().timeIntervalSince(createdAt)
        let idleTime = Date().timeIntervalSince(lastActivity)

        // Check handshake timeout (stricter for stuck TLS connections)
        if !handshakeComplete {
            if age > handshakeTimeout { return true }
        }

        // Check data idle timeout (more lenient for slow responses)
        if handshakeComplete {
            if idleTime > dataIdleTimeout { return true }
        }

        return false
    }

    private func updateActivity() {
        lastActivity = Date()
    }

    private func markHandshakeComplete() {
        handshakeComplete = true
        updateActivity()
    }

    // MARK: - MITM Bypass List
    // Domains in this list will be tunneled directly through Clash without MITM interception.
    // This is useful for:
    // 1. Domains with routing issues (e.g. Google Ads resolving to blocked Chinese IPs)
    // 2. Domains that cause infinite retry loops
    // 3. Domains we don't need to inspect
    private static let bypassDomains: Set<String> = [
        "googleads.g.doubleclick.net",
        "pagead2.googlesyndication.com",
        "adservice.google.com",
        "google-analytics.com",
        "googleadservices.com",
        "static.doubleclick.net",
        "ad.doubleclick.net",
        "cm.g.doubleclick.net",
        "ade.googlesyndication.com",
        "tpc.googlesyndication.com",
        "mads.amazon-adsystem.com",
        "securepubads.g.doubleclick.net"
    ]

    private func shouldBypassMITM(_ host: String) -> Bool {
        // First check blacklist (always bypass these domains)
        if Self.bypassDomains.contains(host) {
            return true
        }
        for domain in Self.bypassDomains {
            if host.hasSuffix("." + domain) {
                return true
            }
        }

        // If whitelist is empty, intercept all (default behavior)
        if cachedWhitelist.isEmpty {
            return false
        }

        let hostLower = host.lowercased()

        // Check if host matches any whitelist entry
        for pattern in cachedWhitelist {
            // Exact match
            if hostLower == pattern {
                return false  // Don't bypass - intercept this host
            }
            // Suffix match (for subdomains)
            if hostLower.hasSuffix("." + pattern) {
                return false  // Don't bypass - intercept this host
            }
            // Pattern match (for wildcard-like behavior)
            if pattern.hasPrefix("*") {
                let suffix = String(pattern.dropFirst())
                if hostLower.hasSuffix(suffix) {
                    return false
                }
            }
        }

        // Host not in whitelist, bypass MITM
        return true
    }

    init(id: UUID, clientConnection: NWConnection, clashPort: UInt16, cachedWhitelist: [String], resilienceEnabled: Bool) {
        self.clashPort = clashPort
        self.clientConnection = clientConnection
        self.cachedWhitelist = cachedWhitelist
        self.resilienceEnabled = resilienceEnabled
    }

    func start() {
        // Debug Log
        // Starting new connection

        clientConnection.stateUpdateHandler = { [weak self] state in
             guard let self = self else { return }
             // Debug Log
             // Client state update
             Task { await self.handleClientState(state) }
        }
        clientConnection.start(queue: .global())
        readClient()
    }

    func stop() {
        // CRITICAL: Prevent multiple stop calls
        guard !isStopped else { return }
        isStopped = true

        // Debug Log
        // Stopping connection

        // Remove state handlers to prevent further callbacks
        clientConnection.stateUpdateHandler = nil
        serverConnection?.stateUpdateHandler = nil
        loopbackListener?.stateUpdateHandler = nil
        loopbackConnection?.stateUpdateHandler = nil
        decryptedConnection?.stateUpdateHandler = nil
        upstreamConnection?.stateUpdateHandler = nil

        // Cancel ALL connections to prevent resource leaks
        clientConnection.cancel()
        serverConnection?.cancel()
        loopbackListener?.cancel()
        loopbackConnection?.cancel()
        decryptedConnection?.cancel()
        upstreamConnection?.cancel()

        // Set all to nil to release memory and resources immediately
        serverConnection = nil
        loopbackListener = nil
        loopbackConnection = nil
        decryptedConnection = nil
        upstreamConnection = nil
        buffer.removeAll()

        // Remove from parent actor
        Task {
            await MITMBackend.shared.removeConnection(id: self.id)
        }
    }

    private func handleClientState(_ state: NWConnection.State) {
        // CRITICAL: Check if already stopped
        guard !isStopped else { return }

        switch state {
        case .failed, .cancelled:
            stop()
        default:
            break
        }
    }

    private func readClient() {
        // CRITICAL: Don't read if stopped or piping
        guard !isStopped && !isPiping else { return }

        clientConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            Task {
                if let data = content {
                    // Debug Log
                    // Process data
                    await self.processClientData(data)
                }
                if isComplete || error != nil {
                    // Log error if needed, or just stop
                    await self.stop()
                } else {
                    await self.readClient()
                }
            }
        }
    }

    private func processClientData(_ data: Data) async {
        if targetHost.isEmpty {
            await handlePayload(data)
        } else {
            serverConnection?.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    private func handlePayload(_ data: Data) async {
        buffer.append(data)
        // Buffer size check

        // Search for double CRLF in Data directly
        let separator = "\r\n\r\n".data(using: .utf8)!
        guard let range = buffer.range(of: separator) else { return }

        let headerData = buffer[..<range.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else { return }

        // Header parsed

        let lines = header.components(separatedBy: "\r\n")
        guard let line = lines.first else { stop(); return }
        // Request line parsed

        let parts = line.components(separatedBy: " ")
        if parts.count >= 2 && parts[0] == "CONNECT" {
            let hp = parts[1].components(separatedBy: ":")
            if hp.count == 2, let p = UInt16(hp[1]) {
                self.targetHost = hp[0]
                self.targetPort = NWEndpoint.Port(rawValue: p)!

                await MITMBackend.shared.reportInterception(MITMInterceptedData(host: targetHost, method: "CONNECT", path: "/"))

                // Check if this domain should bypass MITM
                if shouldBypassMITM(targetHost) {
                    // Bypass MITM silently for known domains
                    self.isPiping = true
                    connectUpstream(isPlain: false)
                } else if targetPort == 443 {
                    // Reduced logging for performance
                    // DEBUG: Log AI-related domains OR IP addresses
                    // if targetHost.contains("googleapis") || targetHost.contains("anthropic") {
                    //     print("[MITMBackend] 🤖 AI TRAFFIC DETECTED: \(targetHost) - Starting TLS interception")
                    // }
                    // DEBUG: Log ALL HTTPS connections to catch IP-based ones
                    // Check if targetHost looks like an IP address
                    // let isIP = targetHost.first?.isNumber ?? false
                    // if isIP {
                    //     print("[MITMBackend] 📡 HTTPS via IP: \(targetHost) - TLS will intercept")
                    // }
                    // CRITICAL: Stop readClient from stealing subsequent data (ServerHello/ClientHello)
                    self.isPiping = true

                    // CRITICAL: Extract remaining data (e.g. ClientHello) that came with CONNECT
                    let remainingData = buffer.count > range.upperBound ? buffer[range.upperBound...] : Data()
                    // DEBUG: await MITMBackend.shared.reportInterception(MITMInterceptedData(host: targetHost, method: "DEBUG", path: "Extracted \(remainingData.count) bytes"))
                    startTLS(initialData: remainingData)
                } else {
                    connectUpstream(isPlain: false)
                }
            }
        } else {
            self.targetPort = 80
            for l in lines where l.lowercased().hasPrefix("host: ") {
                let hostLine = String(l.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                let components = hostLine.components(separatedBy: ":")
                if components.count == 2, let p = UInt16(components[1]) {
                    self.targetHost = components[0]
                    self.targetPort = NWEndpoint.Port(rawValue: p)!
                } else {
                    self.targetHost = hostLine
                }
            }

            // HTTP Target parsed

            await MITMBackend.shared.reportInterception(MITMInterceptedData(host: targetHost, method: "HTTP", path: "/"))
            connectUpstream(isPlain: true)
        }
    }

    private func connectUpstream(isPlain: Bool) {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: clashPort)!)

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // CRITICAL: Avoid System Proxy loop for localhost connection
        params.preferNoProxies = true
        let conn = NWConnection(to: endpoint, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { await self.handleServerState(state, conn: conn, isPlain: isPlain) }
        }
        self.serverConnection = conn
        conn.start(queue: .global())
    }

    private func handleServerState(_ state: NWConnection.State, conn: NWConnection, isPlain: Bool) {
        switch state {
        case .ready:
            if isPlain {
                conn.send(content: self.buffer, completion: .contentProcessed({ [weak self] _ in
                    guard let self = self else { return }
                    Task { await self.setupPipe(c: self.clientConnection, s: conn) }
                }))
            } else {
                handshake(conn)
            }
        case .failed, .cancelled:
            stop()
        default:
            break
        }
    }

    private func handshake(_ conn: NWConnection) {
        let tHost = self.targetHost
        let tPort = self.targetPort
        let req = "CONNECT \(tHost):\(tPort) HTTP/1.1\r\nHost: \(tHost):\(tPort)\r\n\r\n"

        conn.send(content: req.data(using: .utf8), completion: .contentProcessed({ [weak self] err in
            guard let self = self else { return }
            if err != nil { Task { await self.stop() }; return }

            conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, _, _ in
                guard let self = self else { return }
                Task {
                    if let data = content, String(data: data, encoding: .utf8)?.contains("200") == true {
                        let ok = "HTTP/1.1 200 Connection Established\r\n\r\n"
                        self.clientConnection.send(content: ok.data(using: .utf8), completion: .contentProcessed({ [weak self] _ in
                            guard let self = self else { return }
                            Task { await self.setupPipe(c: self.clientConnection, s: conn) }
                        }))
                    } else {
                        await self.stop()
                    }
                }
            }
        }))
    }

    private func startTLS(initialData: Data) {
        let host = self.targetHost
        Task {
            do {
                let identity = try await CertificateManager.shared.getIdentity(for: host)
                // Reduced logging for performance
                // print("[MITMBackend] 🔐 Identity loaded for \(host)")
                self.finalizeTLS(identity, initialData: initialData)
            } catch {
                print("[MITMBackend] ❌ Failed to load identity for \(host): \(error)")
                self.stop()
            }
        }
    }

    private func finalizeTLS(_ identity: SecIdentity, initialData: Data) {
        let options = NWProtocolTLS.Options()
        // SecIdentity can be used directly with sec_protocol_options
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, sec_identity_create(identity)!)

        // Disable session tickets
        sec_protocol_options_set_tls_tickets_enabled(options.securityProtocolOptions, false)

        // Strategy: Use REAL SNI for the local listener to ensure browser compatibility.
        // session-isolation mechanism was causing handshake failures with strict clients.
        sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, self.targetHost)

        // Explicitly disable peer authentication
        sec_protocol_options_set_peer_authentication_required(options.securityProtocolOptions, false)

        // Enforce TLS 1.2 or 1.3
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options.securityProtocolOptions, .TLSv13)

        // Enable both H2 and HTTP/1.1 for better compatibility
        sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, "h2")
        sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, "http/1.1")

        let params = NWParameters(tls: options)
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params, on: .any)

            listener.newConnectionHandler = { [weak self] dec in
                Task { await self?.handleDecrypted(dec) }
            }

            listener.stateUpdateHandler = { [weak self] state in
                Task { await self?.handleLoopbackState(state, listener: listener, initialData: initialData) }
            }

            self.loopbackListener = listener
            listener.start(queue: .global())
            // Reduced logging for performance
            // print("[MITMBackend] 👂 Loopback TLS listener started")
        } catch {
            print("[MITMBackend] ❌ Failed to start loopback listener: \(error)")
            stop()
        }
    }


    private func handleLoopbackState(_ state: NWListener.State, listener: NWListener, initialData: Data) {
        if case .ready = state, let port = listener.port {
             // Reduced logging for performance
             // print("[MITMBackend] ✅ Loopback Listener Ready on port \(port)")
             connectLoopback(port: port, initialData: initialData)
        } else if case .failed(let error) = state {
             print("[MITMBackend] ❌ Loopback Listener Failed: \(error)")
             stop()
        }
    }

    private func connectLoopback(port: NWEndpoint.Port, initialData: Data) {
        // CRITICAL: Check if stopped before proceeding
        guard !isStopped else { return }

        // 1. Reply 200 to Client
        let ok = "HTTP/1.1 200 Connection Established\r\n\r\n"
        clientConnection.send(content: ok.data(using: .utf8), completion: .contentProcessed({ [weak self] _ in
            guard let self = self else { return }

            Task {
                // CRITICAL: Check if stopped inside the async context
                guard await !self.isStopped else { return }

                // Use plain TCP for loopback - the listener will terminate the TLS
                // from the original client's stream. Do NOT add TLS here or we get double-TLS.
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let conn = NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: params)
                await self.setLoopbackConnection(conn)

                conn.stateUpdateHandler = { [weak self] state in
                    guard let self = self else { return }
                    Task {
                        switch state {
                        case .ready:
                             // Reduced logging for performance
                             // print("[MITMBackend] 🔗 Loopback Connection READY")
                             // CRITICAL: If we have initial data (ClientHello), send it to loopback first!
                             if !initialData.isEmpty {
                                 conn.send(content: initialData, completion: .contentProcessed({ _ in
                                     Task { await self.setupPipe(c: self.clientConnection, s: conn) }
                                 }))
                             } else {
                                 await self.setupPipe(c: self.clientConnection, s: conn)
                             }
                        case .failed, .cancelled:
                            await self.stop()
                        default:
                            break
                        }
                    }
                }
                conn.start(queue: .global())
                // Reduced logging for performance
                // print("[MITMBackend] 🔄 ConnectLoopback: Connecting to \(port)...")
            }
        }))
    }

    // Helper to set loopback connection from detached task
    private func setLoopbackConnection(_ conn: NWConnection) {
        self.loopbackConnection = conn
    }

    private func handleDecrypted(_ decrypted: NWConnection) {
        // CRITICAL: Check if stopped before proceeding
        guard !isStopped else {
            decrypted.cancel()
            return
        }

        // OPTIMIZATION: Cancel the loopback listener immediately after accepting the connection
        // This releases the port back to the system, preventing port exhaustion
        loopbackListener?.cancel()
        loopbackListener = nil

        let host = self.targetHost
        let port = self.targetPort

        // Use NWProxyConfig to tunnel through Clash
        Task {
            await self.connectUpstreamTLS(host: host, port: port, decrypted: decrypted)
        }
    }

    private func connectUpstreamTLS(host: String, port: NWEndpoint.Port, decrypted: NWConnection) async {
        // Direct connection to target.
        // The loop prevention must be handled by Clash rules (PROCESS-NAME != Ares).

        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, host)

        // Disable session tickets to prevent resumption issues
        sec_protocol_options_set_tls_tickets_enabled(options.securityProtocolOptions, false)

        let params = NWParameters(tls: options)
        // WARN: We MUST use proxies (Clash) to reach blocked domains.
        // The loop prevention is handled by Clash's "PROCESS-NAME != Ares" rule or similar mechanism.
        // If we force preferNoProxies = true, we bypass Clash and fail to connect to GFW blocked sites.
        params.preferNoProxies = false

        let upstream = NWConnection(to: .hostPort(host: .init(host), port: port), using: params)
        self.setUpstreamConnection(upstream: upstream, decrypted: decrypted)
        upstream.start(queue: .global())
    }

    private func setUpstreamConnection(upstream: NWConnection, decrypted: NWConnection) {
        self.decryptedConnection = decrypted
        self.upstreamConnection = upstream

        // Use a class for thread-safe state tracking (Swift 6 compatible)
        final class ConnectionState: @unchecked Sendable {
            private let lock = NSLock()
            private var _upstreamReady = false
            private var _decryptedReady = false

            var upstreamReady: Bool {
                get { lock.withLock { _upstreamReady } }
                set { lock.withLock { _upstreamReady = newValue } }
            }

            var decryptedReady: Bool {
                get { lock.withLock { _decryptedReady } }
                set { lock.withLock { _decryptedReady = newValue } }
            }

            var bothReady: Bool { lock.withLock { _upstreamReady && _decryptedReady } }
        }

        let state = ConnectionState()

        let checkAndStartPipe = { [weak self] in
            guard let self = self else { return }
            if state.bothReady {
                Task { await self.setupPipe(c: decrypted, s: upstream) }
            }
        }

        upstream.stateUpdateHandler = { [weak self] stateValue in
            guard self != nil else { return }
            switch stateValue {
            case .ready:
                state.upstreamReady = true
                checkAndStartPipe()
            case .failed, .cancelled:
                Task { await self?.stop() }
            default:
                break
            }
        }

        decrypted.stateUpdateHandler = { [weak self] stateValue in
            guard self != nil else { return }
            switch stateValue {
            case .ready:
                state.decryptedReady = true
                checkAndStartPipe()
            case .failed, .cancelled:
                Task { await self?.stop() }
            default:
                break
            }
        }

        decrypted.start(queue: .global())
    }

    // State for pipe and analysis moved to top of class to avoid re-declaration


    private func setupPipe(c: NWConnection, s: NWConnection, log: Bool = true) {
        // CRITICAL: Check if stopped before starting pipe
        guard !isStopped else { return }
        self.isPiping = true
        markHandshakeComplete()

        // Reset state for new pipe
        self.firstRequestReported = false
        self.currentRequestId = nil
        self.firstResponseReported = false
        self.requestStartTime = Date()
        self.responseAccumulator = Data()
        self.cachedRequest = nil // Clear cached request for a new pipe
        self.retryCount = 0 // Reset retry count for a new pipe
        self.isRetrying = false // Ensure this is false at the start of a new pipe

        // Check if we have data to send immediately (Retry Logic)
        if let retryData = self.dataToSendOnRetry {
            print("[MITMBackend] 🔄 Resending \(retryData.count) bytes for retry...")
            s.send(content: retryData, completion: .contentProcessed({ [weak self] sendErr in
                if sendErr != nil { Task { await self?.stop() } }
            }))
            self.dataToSendOnRetry = nil
        }

        // Start bidirectional loops
        rc(c: c, s: s, log: log)
        rs(c: c, s: s, log: log)
    }

    private func rc(c: NWConnection, s: NWConnection, log: Bool) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, i, err in
            guard let self = self else { return }
            Task {
                await self.handleClientPipeData(d: d, isComplete: i, error: err, client: c, server: s, log: log)
            }
        }
    }

    private func rs(c: NWConnection, s: NWConnection, log: Bool) {
        s.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, i, err in
            guard let self = self else { return }
            Task {
                await self.handleServerPipeData(d: d, isComplete: i, error: err, client: c, server: s, log: log)
            }
        }
    }

    private func handleClientPipeData(d: Data?, isComplete: Bool, error: Error?, client: NWConnection, server: NWConnection, log: Bool) async {
        guard !isStopped else { return }

        if let d = d {
            if resilienceEnabled {
                if cachedRequest == nil { cachedRequest = d }
                else { cachedRequest?.append(d) }
            }

            if log && !firstRequestReported {
                let host = targetHost
                if let parsed = await MainActor.run(body: { HTTPParser.parseRequest(d) }) {
                    let validMethods = ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"]
                    if validMethods.contains(parsed.method) {
                        firstRequestReported = true
                        var data = await MainActor.run(body: { MITMInterceptedData(host: host, method: parsed.method, path: parsed.path) })
                        currentRequestId = data.id
                        data.requestHeaders = parsed.headers
                        data.requestSize = d.count

                        // Local copies for async context
                        let method = parsed.method
                        let headers = parsed.headers
                        let bodyOffset = parsed.bodyOffset

                        if ["POST", "PUT", "PATCH"].contains(method) {
                            let ct = headers.first { $0.key.lowercased() == "content-type" }?.value
                            if await MainActor.run(body: { HTTPParser.isTextContent(ct) }) && d.count > bodyOffset {
                                let body = d[bodyOffset...]
                                if await MainActor.run(body: { body.count <= HTTPParser.maxBodyCapture }) { data.requestBody = body }
                            }
                        }
                        await MITMBackend.shared.reportInterception(data)
                    }
                }
            }

            server.send(content: d, completion: .contentProcessed({ [weak self] err in
                if err != nil { Task { await self?.stop() } }
            }))
        }

        if isComplete || error != nil {
            stop()
        } else {
            rc(c: client, s: server, log: log)
        }
    }

    private func handleServerPipeData(d: Data?, isComplete: Bool, error: Error?, client: NWConnection, server: NWConnection, log: Bool) async {
        guard !isStopped else { return }

        if let d = d {
            let maxAcc = 512 * 1024
            if log && firstRequestReported && !firstResponseReported {
                responseAccumulator.append(d)
                if responseAccumulator.count > maxAcc { firstResponseReported = true }

                if responseAccumulator.count >= 100 {
                    let accumulator = responseAccumulator
                    let host = targetHost
                    let reqStartTime = requestStartTime
                    let reqId = currentRequestId
                    let isResilienceOn = resilienceEnabled
                    let currentRetry = retryCount

                    if let parsed = await MainActor.run(body: { HTTPParser.parseResponse(accumulator) }), let requestId = reqId {
                        let isChunked = parsed.headers.contains { $0.key.lowercased() == "transfer-encoding" && $0.value.lowercased().contains("chunked") }
                        let cl = (parsed.headers.first { $0.key.lowercased() == "content-length" }?.value).flatMap { Int($0) }

                        let shouldWait: Bool
                        let bodySize = accumulator.count > parsed.bodyOffset ? accumulator.count - parsed.bodyOffset : 0
                        if isChunked { shouldWait = bodySize < 10 && accumulator.count < 10000 }
                        else if let cLen = cl { shouldWait = bodySize < cLen && accumulator.count < 10000 }
                        else { shouldWait = bodySize <= 0 && accumulator.count < 5000 }

                        if !shouldWait {
                            firstResponseReported = true

                            // Check Resilience
                            let statusCode = parsed.statusCode

                            let isServerError = [500, 502, 503, 504].contains(statusCode)
                            let isRateLimit = statusCode == 429

                            if isResilienceOn && (isServerError || isRateLimit) && currentRetry < MITMBoundConnection.maxRetries {
                                isRetrying = true
                                retryCount += 1
                                let delay: TimeInterval
                                if isRateLimit {
                                    let ra = parsed.headers.first { $0.key.lowercased() == "retry-after" }?.value
                                    delay = (ra.flatMap { Double($0) }) ?? 1.0
                                    print("[MITMBackend] 🛡️ 429 Rate Limit. Backing off for \(delay)s (Attempt \(self.retryCount))")
                                } else {
                                    delay = pow(2.0, Double(retryCount - 1))
                                    print("[MITMBackend] 🛡️ Server Error \(parsed.statusCode). Retrying in \(delay)s (Attempt \(self.retryCount))")
                                }

                                Task {
                                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                    await self.performRetry(client: client, server: server)
                                }
                                return
                            }

                            var data = await MainActor.run(body: { MITMInterceptedData(host: host, method: "RESPONSE", path: "/") })
                            data.id = requestId
                            data.statusCode = parsed.statusCode
                            data.responseHeaders = parsed.headers
                            data.duration = Date().timeIntervalSince(reqStartTime)
                            data.responseSize = accumulator.count

                            let ct = parsed.headers.first { $0.key.lowercased() == "content-type" }?.value
                            if await MainActor.run(body: { HTTPParser.isTextContent(ct) }) && accumulator.count > parsed.bodyOffset {
                                var bodyData = Data(accumulator[parsed.bodyOffset...])
                                if isChunked {
                                    let chunkedData = bodyData
                                    bodyData = await MainActor.run(body: { HTTPParser.decodeChunkedBody(chunkedData) ?? chunkedData })
                                }
                                let ce = parsed.headers.first { $0.key.lowercased() == "content-encoding" }?.value.lowercased()
                                if let enc = ce {
                                    if enc.contains("gzip") || enc.contains("deflate") {
                                        let gzipData = bodyData
                                        bodyData = await MainActor.run(body: { HTTPParser.decompressGzip(gzipData) ?? gzipData })
                                    }
                                    else if enc.contains("br") {
                                        let brData = bodyData
                                        bodyData = await MainActor.run(body: { HTTPParser.decompressBrotli(brData) ?? brData })
                                    }
                                }
                                let finalBody = bodyData
                                if await MainActor.run(body: { finalBody.count <= HTTPParser.maxBodyCapture }) { data.responseBody = finalBody }
                            }
                            await MITMBackend.shared.reportResponse(requestId: requestId, data: data)
                        }
                    }
                }
            }

            client.send(content: d, completion: .contentProcessed({ [weak self] err in
                if err != nil { Task { await self?.stop() } }
            }))
        }

        if isComplete || error != nil {
            stop()
        } else if !isRetrying {
            rs(c: client, s: server, log: log)
        }
    }

    private func performRetry(client: NWConnection, server: NWConnection) async {
        guard let requestData = self.cachedRequest else {
            print("[MITMBackend] ❌ Retry failed: No cached request data")
            return
        }
        print("[MITMBackend] 🛡️ Retrying connection (\(retryCount)/\(MITMBoundConnection.maxRetries))...")

        // 1. Close old server connection
        server.cancel()
        self.serverConnection = nil
        self.upstreamConnection = nil // Also clear upstream if it was set
        self.decryptedConnection = nil // Also clear decrypted if it was set

        // 2. Reset state for a new connection attempt
        self.isRetrying = false // Reset for next attempt
        self.handshakeComplete = false
        self.dataToSendOnRetry = requestData // Store data to be sent on the new connection

        // 3. Trigger new upstream connection
        // This will eventually call setupPipe again, which will then send dataToSendOnRetry
        self.connectUpstream(isPlain: false)

        print("[MITMBackend] 🔄 Retry sequence initiated. Waiting for new connection...")
    }


}
