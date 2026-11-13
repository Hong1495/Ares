import Foundation
import SubscriptionKit

/// Checks socket ownership, not only connectability. Does not signal or reconfigure any process.
enum ListenerVerification {
    static func verify(configuration: String, apiPort: Int, ownedPIDs: Set<Int32>) async throws {
        let endpoints = try EgressConfiguration.endpoints(configuration: configuration)
        guard !endpoints.isEmpty else { return }
        guard !ownedPIDs.isEmpty else { throw URLError(.cannotConnectToHost) }
        let runner = ProcessManager()
        let args = ["-nP", "-a", "-p", ownedPIDs.sorted().map(String.init).joined(separator: ","), "-i", "-F", "pPn"]
        var result = try await runner.run(executable: "/usr/sbin/lsof", arguments: args, timeout: 5)
        if !matches(result.output, endpoints: endpoints, apiPort: apiPort) {
            // Existing TUN authorization may permit inspection; never request new privileges here.
            result = try await runner.run(executable: "/usr/bin/sudo", arguments: ["-n", "/usr/sbin/lsof"] + args, timeout: 5)
        }
        guard matches(result.output, endpoints: endpoints, apiPort: apiPort) else { throw URLError(.cannotConnectToHost) }
    }
    static func matches(_ output: String, endpoints: [EgressConfiguration.Endpoint], apiPort: Int) -> Bool {
        var pid = "", transport = ""
        var sockets: [String: Set<String>] = [:]
        for line in output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("p") { pid = String(line.dropFirst()) }
            else if line.hasPrefix("P") { transport = String(line.dropFirst()).lowercased() }
            else if line.hasPrefix("n"), !line.contains("->") {
                let address = String(line.dropFirst()).replacingOccurrences(of: " (LISTEN)", with: "")
                sockets[pid, default: []].insert(transport + ":" + address)
            }
        }
        let apiSuffix = ":\(apiPort)"
        return sockets.values.contains { owned in
            guard owned.contains(where: { $0.hasPrefix("tcp:") && $0.hasSuffix(apiSuffix) }) else { return false }
            return endpoints.allSatisfy { endpoint in
                let host = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
                let exact = "\(endpoint.transport):\(host):\(endpoint.port)"
                let wildcard = "\(endpoint.transport):*:\(endpoint.port)"
                return owned.contains(exact) || (["0.0.0.0", "::", "*"].contains(endpoint.host) && owned.contains(wildcard))
            }
        }
    }
}
