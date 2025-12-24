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
    private var onInterception: ((String, String, String) -> Void)?
    
    private init() {}
    
    // MARK: - API
    
    func setCallbacks(
        statusUpdate: @escaping (Bool, UInt16) -> Void,
        interception: @escaping (String, String, String) -> Void
    ) {
        self.onStatusUpdate = statusUpdate
        self.onInterception = interception
    }
    
    func start(clashPort: UInt16) async {
        await stop()
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: .any)
            
            // Debug Log
            // listener created successfully
            
            listener.newConnectionHandler = { [weak self] nwConn in
                // Use Task.detached to prevent any accidental actor context inheritance
                Task.detached {
                    await self?.createNewConnection(nwConn, clashPort: clashPort)
                }
            }
            
            listener.stateUpdateHandler = { [weak self] state in
                // Debug Log
                // Listener state update
                Task.detached {
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
        listener?.cancel()
        listener = nil
        
        // Copy values to avoid concurrent access issues during iteration ?
        // Actually we are ON the actor, so access is safe.
        let conns = connections.values
        connections.removeAll()
        
        for conn in conns {
            // This is an async call to another actor
            await conn.stop()
        }
        
        updateStatus(running: false, port: 0)
    }
    
    // MARK: - Internal
    
    // Actor-isolated method
    func createNewConnection(_ nwConn: NWConnection, clashPort: UInt16) async {
        let conn = MITMBoundConnection(connection: nwConn, clashPort: clashPort)
        let id = conn.id
        connections[id] = conn
        await conn.start()
    }
    
    func removeConnection(id: UUID) {
        connections.removeValue(forKey: id)
    }
    
    func reportInterception(host: String, method: String, path: String) {
        // Debug Log
        // Reporting interception
        onInterception?(host, method, path)
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
    
    init(connection: NWConnection, clashPort: UInt16) {
        self.clientConnection = connection
        self.clashPort = clashPort
    }
    
    func start() {
        // Debug Log
        // Starting new connection
        
        clientConnection.stateUpdateHandler = { [weak self] state in
             guard let self = self else { return }
             // Debug Log
             // Client state update
             Task.detached { await self.handleClientState(state) }
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
        
        // Clean up references
        serverConnection = nil
        loopbackListener = nil
        loopbackConnection = nil
        decryptedConnection = nil
        upstreamConnection = nil
        buffer.removeAll()
        
        // Remove from parent actor
        Task.detached {
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
            
            Task.detached {
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
                
                await MITMBackend.shared.reportInterception(host: targetHost, method: "CONNECT", path: "/")
                
                if targetPort == 443 {
                    // CRITICAL: Stop readClient from stealing subsequent data (ServerHello/ClientHello)
                    self.isPiping = true
                    
                    // CRITICAL: Extract remaining data (e.g. ClientHello) that came with CONNECT
                    let remainingData = buffer.count > range.upperBound ? buffer[range.upperBound...] : Data()
                    await MITMBackend.shared.reportInterception(host: targetHost, method: "DEBUG", path: "Extracted \(remainingData.count) bytes of initial data")
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
            
            await MITMBackend.shared.reportInterception(host: targetHost, method: "HTTP", path: "/")
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
            Task.detached { await self.handleServerState(state, conn: conn, isPlain: isPlain) }
        }
        self.serverConnection = conn
        conn.start(queue: .global())
    }
    
    private func handleServerState(_ state: NWConnection.State, conn: NWConnection, isPlain: Bool) {
        if case .ready = state {
            if isPlain {
                conn.send(content: self.buffer, completion: .contentProcessed({ [weak self] _ in
                    guard let self = self else { return }
                    Task.detached { await self.setupPipe(c: self.clientConnection, s: conn) }
                }))
            } else {
                handshake(conn)
            }
        } else if case .failed = state {
            stop()
        }
    }
    
    private func handshake(_ conn: NWConnection) {
        let tHost = self.targetHost
        let tPort = self.targetPort
        let req = "CONNECT \(tHost):\(tPort) HTTP/1.1\r\nHost: \(tHost):\(tPort)\r\n\r\n"
        
        conn.send(content: req.data(using: .utf8), completion: .contentProcessed({ [weak self] err in
            guard let self = self else { return }
            if err != nil { Task.detached { await self.stop() }; return }
            
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, _, _ in
                guard let self = self else { return }
                Task.detached {
                    if let data = content, String(data: data, encoding: .utf8)?.contains("200") == true {
                        let ok = "HTTP/1.1 200 Connection Established\r\n\r\n"
                        self.clientConnection.send(content: ok.data(using: .utf8), completion: .contentProcessed({ [weak self] _ in
                            guard let self = self else { return }
                            Task.detached { await self.setupPipe(c: self.clientConnection, s: conn) }
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
        Task.detached {
            do {
                let identity = try await CertificateManager.shared.getIdentity(for: host)
                print("[MITMBackend] 🔐 Identity loaded for \(host)")
                await self.finalizeTLS(identity, initialData: initialData)
            } catch {
                print("[MITMBackend] ❌ Failed to load identity for \(host): \(error)")
                await self.stop()
            }
        }
    }
    
    private func finalizeTLS(_ identity: SecIdentity, initialData: Data) {
        let options = NWProtocolTLS.Options()
        // SecIdentity can be used directly with sec_protocol_options
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, sec_identity_create(identity)!)
        
        // Disable session tickets/resumption
        sec_protocol_options_set_tls_tickets_enabled(options.securityProtocolOptions, false)
        // REMOVED: sec_protocol_options_set_tls_is_fallback_attempt - this might be causing issues
        
        // Disable Client Authentication (Peer Verification)
        sec_protocol_options_set_peer_authentication_required(options.securityProtocolOptions, false)
        
        // Enforce TLS 1.2 or 1.3
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options.securityProtocolOptions, .TLSv13)
        
        // Force HTTP/1.1 to stabilize ALPN negotiation
        sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, "http/1.1")
        
        // Help BoringSSL match the session by providing the Server Name (SNI) we expect
        sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, self.targetHost)
        
        let params = NWParameters(tls: options)
        params.allowLocalEndpointReuse = true
        
        do {
            let listener = try NWListener(using: params, on: .any)
            
            listener.newConnectionHandler = { [weak self] dec in
                Task.detached { await self?.handleDecrypted(dec) }
            }
            
            listener.stateUpdateHandler = { [weak self] state in
                Task.detached { await self?.handleLoopbackState(state, listener: listener, initialData: initialData) }
            }
            
            self.loopbackListener = listener
            listener.start(queue: .global())
            print("[MITMBackend] 👂 Loopback TLS listener started")
        } catch {
            print("[MITMBackend] ❌ Failed to start loopback listener: \(error)")
            stop()
        }
    }
    

    private func handleLoopbackState(_ state: NWListener.State, listener: NWListener, initialData: Data) {
        if case .ready = state, let port = listener.port {
             print("[MITMBackend] ✅ Loopback Listener Ready on port \(port)")
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
            
            Task.detached {
                // CRITICAL: Check if stopped inside the async context
                guard await !self.isStopped else { return }
                
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let conn = NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: params)
                await self.setLoopbackConnection(conn)
                
                conn.stateUpdateHandler = { [weak self] state in
                    guard let self = self else { return }
                    Task.detached {
                        if case .ready = state {
                             print("[MITMBackend] 🔗 Loopback Connection READY")
                             // CRITICAL: If we have initial data (ClientHello), send it to loopback first!
                             if !initialData.isEmpty {
                                 conn.send(content: initialData, completion: .contentProcessed({ _ in
                                     Task.detached { await self.setupPipe(c: self.clientConnection, s: conn) }
                                 }))
                             } else {
                                 await self.setupPipe(c: self.clientConnection, s: conn)
                             }
                        }
                        else if case .failed(let error) = state { 
                            print("[MITMBackend] ❌ Loopback Connection Failed: \(error)")
                            await self.stop() 
                        }
                    }
                }
                conn.start(queue: .global())
                print("[MITMBackend] 🔄 ConnectLoopback: Connecting to \(port)...")
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
        
        let host = self.targetHost
        let port = self.targetPort
        
        // Use NWProxyConfig to tunnel through Clash
        Task.detached {
            await self.connectUpstreamTLS(host: host, port: port, decrypted: decrypted)
        }
    }
    
    private func connectUpstreamTLS(host: String, port: NWEndpoint.Port, decrypted: NWConnection) async {
        // Use System Proxy to route valid upstream traffic
        // This acts as a robust fallback for all macOS versions.
        // It relies on the System Proxy (managed by Clash) to handle the actual routing.
        let options = NWProtocolTLS.Options()
        let params = NWParameters(tls: options)
        // CRITICAL: Bypass System Proxy to prevent infinite loop (MITM -> SystemProxy -> MITM).
        // This relies on Clash TUN mode to intercept the traffic at the network interface level.
        params.preferNoProxies = true
        
        let upstream = NWConnection(to: .hostPort(host: .init(host), port: port), using: params)
        self.setUpstreamConnection(upstream: upstream, decrypted: decrypted)
        upstream.start(queue: .global())
    }

    private func setUpstreamConnection(upstream: NWConnection, decrypted: NWConnection) {
        self.decryptedConnection = decrypted
        self.upstreamConnection = upstream
        
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task.detached {
                if case .ready = state { await self.setupPipe(c: decrypted, s: upstream) }
                else if case .failed = state { await self.stop() }
            }
        }
        
        decrypted.start(queue: .global())
    }
    
    private func setupPipe(c: NWConnection, s: NWConnection, log: Bool = false) {
        // CRITICAL: Check if stopped before starting pipe
        guard !isStopped else { return }
        self.isPiping = true
        
        let capturedHost = self.targetHost
        let capturedStoppedCheck = { [weak self] () -> Bool in
            // Synchronous check for isStopped (can't await in receive callback)
            return self == nil
        }
        
        func rc() {
            // CRITICAL: Don't schedule new receives if stopped
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, i, err in
                // Exit early if actor is gone
                guard self != nil else { return }
                
                if let d = d {
                    if log {
                        // Try to parse HTTP Method and Path from the decrypted data
                        if let firstChunk = String(data: d, encoding: .utf8) {
                            // Look for standard HTTP methods
                            let lines = firstChunk.components(separatedBy: "\r\n")
                            if let firstLine = lines.first, !firstLine.isEmpty {
                                 let parts = firstLine.components(separatedBy: " ")
                                 if parts.count >= 3 {
                                     let method = parts[0]
                                     let path = parts[1]
                                     // Basic filtering for common methods to avoid noise
                                     if ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"].contains(method) {
                                         Task.detached { await MITMBackend.shared.reportInterception(host: capturedHost, method: method, path: path) }
                                     }
                                 }
                            }
                        }
                    }
                    s.send(content: d, completion: .contentProcessed({_ in}))
                }
                
                // CRITICAL: Stop loop on error or completion
                if i || err != nil {
                    Task.detached { await self?.stop() }
                } else if !capturedStoppedCheck() {
                    rc()
                }
            }
        }
        
        func rs() {
            // CRITICAL: Don't schedule new receives if stopped
            s.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, i, err in
                // Exit early if actor is gone
                guard self != nil else { return }
                
                if let d = d {
                    c.send(content: d, completion: .contentProcessed({_ in}))
                }
                
                // CRITICAL: Stop loop on error or completion
                if i || err != nil {
                    Task.detached { await self?.stop() }
                } else if !capturedStoppedCheck() {
                    rs()
                }
            }
        }
        
        rc()
        rs()
    }
}
