import Foundation

extension ClashController {
    /// Set Clash mode (rule/global/direct)
    func setMode(_ mode: ClashConfig.Mode) async throws {
        guard let url = URL(string: "\(baseURL)/configs") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["mode": mode.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await URLSession.shared.data(for: request)

        ClashViewModel.shared.addLog("[ClashController] Set mode to \(mode.rawValue)", level: .debug)
    }

    /// Get current Clash mode
    func getCurrentMode() async throws -> ClashConfig.Mode {
        guard let url = URL(string: "\(baseURL)/configs") else {
            throw NSError(domain: "ClashController", code: 1, userInfo: nil)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let modeString = json?["mode"] as? String,
           let mode = ClashConfig.Mode(rawValue: modeString) {
            return mode
        }

        throw NSError(domain: "ClashController", code: 2, userInfo: nil)
    }

    /// Set Clash log level
    func setLogLevel(_ level: String) async throws {
        guard let url = URL(string: "\(baseURL)/configs") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["log-level": level]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await URLSession.shared.data(for: request)
        ClashViewModel.shared.addLog("[ClashController] Set log level to \(level)")
    }

    /// Fetch active rules from Clash API
    func fetchRules() async throws {
        guard let url = URL(string: "\(baseURL)/rules") else { return }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return
        }

        // Parse rules in background
        let rules = await Task.detached(priority: .utility) {
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let rulesList = json["rules"] as? [[String: Any]] else {
                return [] as [ClashRule]
            }

            var fetchedRules: [ClashRule] = []
            for ruleData in rulesList {
                if let type = ruleData["type"] as? String,
                   let payload = ruleData["payload"] as? String,
                   let proxy = ruleData["proxy"] as? String {
                    let hit = ruleData["hit"] as? Int ?? 0
                    fetchedRules.append(ClashRule(id: UUID(), type: type, payload: payload, proxy: proxy, hit: hit))
                }
            }
            return fetchedRules
        }.value

        self.rules = rules
    }
}
