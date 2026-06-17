import Foundation
import Network

extension MITMBoundConnection {
    func readClient() {
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

    func processClientData(_ data: Data) async {
        if targetHost.isEmpty {
            await handlePayload(data)
        } else {
            serverConnection?.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    func handlePayload(_ data: Data) async {
        buffer.append(data)
        // Buffer size check

        // Search for double CRLF in Data directly
        let separator = Data([13, 10, 13, 10])
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
            if hp.count == 2, let p = UInt16(hp[1]), let port = NWEndpoint.Port(rawValue: p) {
                self.targetHost = hp[0]
                self.targetPort = port

                await MITMBackend.shared.reportInterception(MITMInterceptedData(host: targetHost, method: "CONNECT", path: "/"))

                // Check if this domain should bypass MITM
                if shouldBypassMITM(targetHost) {
                    // Bypass MITM silently for known domains
                    self.isPiping = true
                    connectUpstream(isPlain: false)
                } else if targetPort == 443 {
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
                if components.count == 2, let p = UInt16(components[1]), let port = NWEndpoint.Port(rawValue: p) {
                    self.targetHost = components[0]
                    self.targetPort = port
                } else {
                    self.targetHost = hostLine
                }
            }

            // HTTP Target parsed

            await MITMBackend.shared.reportInterception(MITMInterceptedData(host: targetHost, method: "HTTP", path: "/"))
            connectUpstream(isPlain: true)
        }
    }

    func connectUpstream(isPlain: Bool) {
        guard let port = NWEndpoint.Port(rawValue: clashPort) else {
            stop()
            return
        }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)

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

    func handleServerState(_ state: NWConnection.State, conn: NWConnection, isPlain: Bool) {
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

    func handshake(_ conn: NWConnection) {
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
}
