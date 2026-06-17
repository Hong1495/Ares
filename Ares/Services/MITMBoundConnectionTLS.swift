import Foundation
import Network
import Security

extension MITMBoundConnection {
    func startTLS(initialData: Data) {
        let host = self.targetHost
        Task {
            do {
                let identity = try await CertificateManager.shared.getIdentity(for: host)
                self.finalizeTLS(identity, initialData: initialData)
            } catch {
                Task { @MainActor in
                    ClashViewModel.shared.addLog("[MITMBackend] Failed to load TLS identity: \(error)", level: .debug)
                }
                self.stop()
            }
        }
    }

    func finalizeTLS(_ identity: SecIdentity, initialData: Data) {
        let options = NWProtocolTLS.Options()
        // SecIdentity can be used directly with sec_protocol_options
        guard let localIdentity = sec_identity_create(identity) else {
            Task { @MainActor in
                ClashViewModel.shared.addLog("[MITMBackend] Failed to create TLS identity", level: .debug)
            }
            stop()
            return
        }
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, localIdentity)

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
        } catch {
            Task { @MainActor in
                ClashViewModel.shared.addLog("[MITMBackend] Failed to start loopback listener: \(error)", level: .debug)
            }
            stop()
        }
    }


    func handleLoopbackState(_ state: NWListener.State, listener: NWListener, initialData: Data) {
        if case .ready = state, let port = listener.port {
             connectLoopback(port: port, initialData: initialData)
        } else if case .failed(let error) = state {
             Task { @MainActor in
                 ClashViewModel.shared.addLog("[MITMBackend] Loopback listener failed: \(error)", level: .debug)
             }
             stop()
        }
    }

    func connectLoopback(port: NWEndpoint.Port, initialData: Data) {
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
                             // CRITICAL: If we have initial data (ClientHello), send it to loopback before piping.
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
            }
        }))
    }

    // Helper to set loopback connection from detached task
    func setLoopbackConnection(_ conn: NWConnection) {
        self.loopbackConnection = conn
    }

    func handleDecrypted(_ decrypted: NWConnection) {
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

    func connectUpstreamTLS(host: String, port: NWEndpoint.Port, decrypted: NWConnection) async {
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

    func setUpstreamConnection(upstream: NWConnection, decrypted: NWConnection) {
        self.decryptedConnection = decrypted
        self.upstreamConnection = upstream

        // Use a class for thread-safe state tracking (Swift 6 compatible)
        final class ConnectionState: @unchecked Sendable {
            let lock = NSLock()
            var _upstreamReady = false
            var _decryptedReady = false

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
}
