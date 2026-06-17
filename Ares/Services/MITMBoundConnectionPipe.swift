import Foundation
import Network

extension MITMBoundConnection {
    // State for pipe and analysis moved to top of class to avoid re-declaration


    func setupPipe(c: NWConnection, s: NWConnection, log: Bool = true) {
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
            s.send(content: retryData, completion: .contentProcessed({ [weak self] sendErr in
                if sendErr != nil { Task { await self?.stop() } }
            }))
            self.dataToSendOnRetry = nil
        }

        // Start bidirectional loops
        rc(c: c, s: s, log: log)
        rs(c: c, s: s, log: log)
    }

    func rc(c: NWConnection, s: NWConnection, log: Bool) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, i, err in
            guard let self = self else { return }
            Task {
                await self.handleClientPipeData(d: d, isComplete: i, error: err, client: c, server: s, log: log)
            }
        }
    }

    func rs(c: NWConnection, s: NWConnection, log: Bool) {
        s.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, i, err in
            guard let self = self else { return }
            Task {
                await self.handleServerPipeData(d: d, isComplete: i, error: err, client: c, server: s, log: log)
            }
        }
    }

    func handleClientPipeData(d: Data?, isComplete: Bool, error: Error?, client: NWConnection, server: NWConnection, log: Bool) async {
        guard !isStopped else { return }

        if let d = d {
            if resilienceEnabled {
                if cachedRequest == nil { cachedRequest = d }
                else { cachedRequest?.append(d) }
            }

            if log && !firstRequestReported {
                let host = targetHost
                if let parsed = MITMBackend.parseRequest(d) {
                    let validMethods = ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"]
                    if validMethods.contains(parsed.method) {
                        firstRequestReported = true
                        var data = MITMInterceptedData(host: host, method: parsed.method, path: parsed.path)
                        currentRequestId = data.id
                        data.requestHeaders = parsed.headers
                        data.requestSize = d.count

                        // Local copies for async context
                        let method = parsed.method
                        let headers = parsed.headers
                        let bodyOffset = parsed.bodyOffset

                        if ["POST", "PUT", "PATCH"].contains(method) {
                            let ct = headers.first { $0.key.lowercased() == "content-type" }?.value
                            if MITMBackend.isTextContent(ct) && d.count > bodyOffset {
                                let body = d[bodyOffset...]
                                if body.count <= MITMBackend.maxBodyCapture { data.requestBody = body }
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

    func handleServerPipeData(d: Data?, isComplete: Bool, error: Error?, client: NWConnection, server: NWConnection, log: Bool) async {
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

                    if let parsed = MITMBackend.parseResponse(accumulator), let requestId = reqId {
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
                            } else {
                                delay = pow(2.0, Double(retryCount - 1))
                            }

                                Task {
                                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                    await self.performRetry(client: client, server: server)
                                }
                                return
                            }

                            var data = MITMInterceptedData(host: host, method: "RESPONSE", path: "/")
                            data.id = requestId
                            data.statusCode = parsed.statusCode
                            data.responseHeaders = parsed.headers
                            data.duration = Date().timeIntervalSince(reqStartTime)
                            data.responseSize = accumulator.count

                            let ct = parsed.headers.first { $0.key.lowercased() == "content-type" }?.value
                            if MITMBackend.isTextContent(ct) && accumulator.count > parsed.bodyOffset {
                                var bodyData = Data(accumulator[parsed.bodyOffset...])
                                if isChunked {
                                    let chunkedData = bodyData
                                    bodyData = MITMBackend.decodeChunkedBody(chunkedData) ?? chunkedData
                                }
                                let ce = parsed.headers.first { $0.key.lowercased() == "content-encoding" }?.value.lowercased()
                                if let enc = ce {
                                    if enc.contains("gzip") || enc.contains("deflate") {
                                        let gzipData = bodyData
                                        bodyData = MITMBackend.decompressGzip(gzipData) ?? gzipData
                                    }
                                    else if enc.contains("br") {
                                        let brData = bodyData
                                        bodyData = MITMBackend.decompressBrotli(brData) ?? brData
                                    }
                                }
                                let finalBody = bodyData
                                if finalBody.count <= MITMBackend.maxBodyCapture { data.responseBody = finalBody }
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

    func performRetry(client: NWConnection, server: NWConnection) async {
        guard let requestData = self.cachedRequest else {
            return
        }

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
    }
}
