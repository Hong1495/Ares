import Foundation

extension ClashController {
    /// Fetch and parse proxies from Clash API
    func fetchProxiesData() async throws {
        // Removed noisy log: ClashService.shared.addLog("[ClashController] 📡 Fetching proxy data...")
        let url = URL(string: "\(baseURL)/proxies")!

        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse in background to avoid blocking Main Actor
        let (groups, nodes) = await Task.detached(priority: .userInitiated) {
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let proxiesDict = json["proxies"] as? [String: [String: Any]] else {
                return ([], [:]) as ([ProxyGroup], [String: ProxyNode])
            }

            var groups: [ProxyGroup] = []
            var nodes: [String: ProxyNode] = [:]

            for (name, proxyData) in proxiesDict {
                if let type = proxyData["type"] as? String {
                    // Check if it's a node (has history or delay)
                    if let history = proxyData["history"] as? [[String: Any]] {
                        let delay = history.first?["delay"] as? Int
                        let node = ProxyNode(
                            name: name,
                            type: type,
                            delay: delay
                        )
                        nodes[name] = node
                    }

                    // Parse ALL proxy groups
                    if let all = proxyData["all"] as? [String], !all.isEmpty {
                        let now = proxyData["now"] as? String

                        let group = ProxyGroup(
                            name: name,
                            type: type,
                            now: now,
                            all: all
                        )
                        groups.append(group)
                    }
                }
            }
            return (groups, nodes)
        }.value

        // Update UI state
        self.proxyGroups = groups
        self.proxyNodes = nodes
    }

    /// Select a proxy in a group
    func selectProxy(group: String, proxy: String) async throws {
        ClashViewModel.shared.addLog("[ClashController] 🎯 Selecting proxy: \(proxy) in group: \(group)")

        // Pre-flight check: Ensure Clash API is reachable
        let versionURL = URL(string: "\(baseURL)/version")!
        do {
            let (_, vResp) = try await URLSession.shared.data(from: versionURL)
            if let httpResp = vResp as? HTTPURLResponse, httpResp.statusCode != 200 {
                ClashViewModel.shared.addLog("[ClashController] ❌ Clash API not healthy (HTTP \(httpResp.statusCode)). Is Clash running?")
                return
            }
        } catch {
            ClashViewModel.shared.addLog("[ClashController] ❌ Clash API unreachable at \(baseURL). Is Clash running?")
            return
        }

        // URL encode the group name (contains Chinese/emoji)
        guard let encodedGroup = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/proxies/\(encodedGroup)") else {
            ClashViewModel.shared.addLog("[ClashController] ❌ Failed to encode group: \(group)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["name": proxy]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 204 {
                ClashViewModel.shared.addLog("[ClashController] ✅ Proxy selected successfully")
            } else {
                ClashViewModel.shared.addLog("[ClashController] ⚠️ HTTP \(httpResponse.statusCode)")
            }
        }
    }

    /// Test proxy delay
    func testProxyDelay(name: String, timeout: Int = 5000) async throws -> Int {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/proxies/\(encodedName)/delay?timeout=\(timeout)&url=http://www.gstatic.com/generate_204") else {
            ClashViewModel.shared.addLog("[ClashController] ❌ Invalid proxy name for test: \(name)")
            throw NSError(domain: "ClashController", code: -1)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                ClashViewModel.shared.addLog("[ClashController] ⚠️ Test failed for \(name): HTTP \(httpResp.statusCode)")
                throw NSError(domain: "ClashController", code: httpResp.statusCode)
            }

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let delay = json["delay"] as? Int else {
                throw NSError(domain: "ClashController", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid delay response"])
            }

            // ClashService.shared.addLog("[ClashController] ✅ \(name): \(delay)ms")

            // Update node delay in memory
            await MainActor.run {
                if var node = proxyNodes[name] {
                    node.delay = delay
                    proxyNodes[name] = node
                }
            }
            return delay
        } catch {
            ClashViewModel.shared.addLog("[ClashController] ❌ Test error for \(name): \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch proxies (legacy)
    func fetchProxies() async throws -> [String: Any] {
        try await fetchProxiesData()
        return proxies
    }
}
