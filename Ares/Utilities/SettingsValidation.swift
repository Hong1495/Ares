import Foundation

nonisolated enum SettingsValidation {
    static func error(http: String, socks: String, mixed: String, mtu: Int, keepAlive: Int,
                      udpTimeout: Int, mitmPorts: String, dns: String = "223.5.5.5", device: String = "") -> String? {
        let values = [http, socks, mixed].map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard values.allSatisfy({ $0.map { (1...65535).contains($0) } ?? false }) else {
            return "Proxy ports must be integers from 1 to 65535."
        }
        let ports = values.compactMap { $0 }
        guard Set(ports).count == 3 else { return "HTTP, SOCKS and Mixed ports must be different." }
        guard !ports.contains(where: { [ClashPorts.apiNormal, ClashPorts.apiTun, 1053].contains($0) }) else {
            return "Proxy ports cannot use the controller or DNS listener ports."
        }
        guard (1280...9000).contains(mtu) else { return "MTU must be between 1280 and 9000 bytes." }
        guard (1...86400).contains(keepAlive), (1...86400).contains(udpTimeout) else {
            return "Connection intervals must be between 1 and 86400 seconds."
        }
        let intercept = mitmPorts.split(separator: ",", omittingEmptySubsequences: false)
        guard !intercept.isEmpty, intercept.allSatisfy({ Int($0.trimmingCharacters(in: .whitespaces)).map { (1...65535).contains($0) } ?? false }) else {
            return "Interception ports must be comma-separated integers from 1 to 65535."
        }
        let resolvers = dns.split(separator: ",", omittingEmptySubsequences: false)
        guard !resolvers.isEmpty, resolvers.allSatisfy({
            let value = $0.trimmingCharacters(in: .whitespaces)
            return !value.isEmpty && !value.contains(where: { $0.isWhitespace || $0.isNewline })
        }) else { return "Enter one or more DNS resolvers, separated by commas." }
        guard device.isEmpty || device.range(of: "^utun[0-9]+$", options: .regularExpression) != nil else {
            return "Use a macOS interface name such as utun9, or leave it empty for automatic selection."
        }
        return nil
    }
}
