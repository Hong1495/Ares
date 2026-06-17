import Foundation

extension ClashController {
    /// Start monitoring traffic via WebSocket
    func startTrafficMonitor() {
        guard !isMonitoring else { return }

        stopTrafficMonitor()
        isMonitoring = true

        ClashViewModel.shared.addLog("[ClashController] 🟢 Starting traffic monitor (WebSocket)")

        let url = URL(string: "ws://127.0.0.1:\(currentPort)/traffic?token=")
        guard let wsUrl = url else { return }

        trafficWebSocket = URLSession.shared.webSocketTask(with: wsUrl)
        trafficWebSocket?.resume()

        receiveTrafficMessage()
    }

    func stopTrafficMonitor() {
        isMonitoring = false
        trafficWebSocket?.cancel(with: .goingAway, reason: "Monitoring stopped".data(using: .utf8))
        trafficWebSocket = nil
        // Reset traffic stats to 0 when stopped
        DispatchQueue.main.async {
            self.traffic = TrafficStats()
        }
    }

    private func restartMonitor() {
        guard isMonitoring else { return }
        // Don't call stopTrafficMonitor() here as it sets isMonitoring=false
        trafficWebSocket?.cancel(with: .goingAway, reason: nil)
        trafficWebSocket = nil

        let url = URL(string: "ws://127.0.0.1:\(currentPort)/traffic?token=")
        guard let wsUrl = url else { return }

        trafficWebSocket = URLSession.shared.webSocketTask(with: wsUrl)
        trafficWebSocket?.resume()

        receiveTrafficMessage()
    }

    private func receiveTrafficMessage() {
        guard isMonitoring, let ws = trafficWebSocket else { return }

        // Offload the WebSocket receive loop to a background thread
        Task.detached(priority: .medium) { [weak self] in
            guard let self = self else { return }

            while await self.isMonitoring {
                let isForeground = await MainActor.run { AppState.shared.isForeground }
                if !isForeground {
                    await MainActor.run { self.stopTrafficMonitor() }
                    break
                }
                // accessing trafficWebSocket needs to be thread-safe or carefully managed.
                // Since trafficWebSocket is internal and not an actor, we should be careful.
                // ideally, we should grab the reference once.

                guard let currentWS = await self.trafficWebSocket, currentWS === ws else { break }

                do {
                    let message = try await currentWS.receive()

                    // Throttle updates to reduce Main Thread CPU
                    let now = Date()
                    let lastUpdate = await self.lastTrafficUpdate
                    if now.timeIntervalSince(lastUpdate) < 1.0 {
                        continue
                    }

                    // Parse in background
                    if let stats = self.parseTrafficMessage(message) {
                        // Update UI on MainActor
                        await MainActor.run {
                            self.consecutiveFailures = 0
                            self.lastTrafficStats = stats
                            self.traffic = stats
                            self.lastTrafficUpdate = now
                        }
                    }

                } catch {
                    // removing await self.isMonitoring check here as we check at start of loop
                    // but we need to check if we should break
                    let stillMonitoring = await self.isMonitoring
                    guard stillMonitoring, let currentWS = await self.trafficWebSocket, currentWS === ws else { break }

                    await MainActor.run {
                        self.consecutiveFailures += 1

                        let nsError = error as NSError
                        if nsError.code != 57 && nsError.code != -999 {
                            ClashViewModel.shared.addLog("[ClashController] ⚠️ Traffic WebSocket error (\(self.consecutiveFailures)/\(self.MAX_RETRY_FAILURES)): \(error.localizedDescription)")
                        }

                        if self.consecutiveFailures >= self.MAX_RETRY_FAILURES {
                            ClashViewModel.shared.addLog("[ClashController] 🛑 Max retry failures reached, stopping monitor")
                            self.stopTrafficMonitor()
                        }
                    }

                    let cf = await self.consecutiveFailures
                    let maxRetry = self.MAX_RETRY_FAILURES
                    if cf >= maxRetry { break }

                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s wait

                    let isMonitoring = await self.isMonitoring
                    let isRunning = await ClashViewModel.shared.isRunning
                    if isMonitoring && isRunning {
                        await MainActor.run { self.restartMonitor() }
                    }
                    break
                }
            }
        }
    }

    // Pure parsing function (thread-safe)
    nonisolated private func parseTrafficMessage(_ message: URLSessionWebSocketTask.Message) -> TrafficStats? {
        let data: Data?
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8)
        @unknown default: data = nil
        }

        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let up = json["up"] as? Int64,
              let down = json["down"] as? Int64 else {
            return nil
        }

        return TrafficStats(up: up, down: down)
    }

    /// Deprecated: HTTP polling
    func fetchTraffic() async throws {
        // No-op
    }
}
