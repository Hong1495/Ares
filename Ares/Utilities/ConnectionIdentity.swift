import Foundation

nonisolated struct ConnectionIdentity: Equatable, Sendable {
    let key: String
    let name: String
    let iconPath: String?

    init(path: String?, process: String?, source: String) {
        let path = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let process = process?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var bundle = ""
        if path.hasPrefix("/") {
            for component in path.split(separator: "/") {
                bundle += "/" + component
                if component.hasSuffix(".app") { break }
            }
        }
        if bundle.hasSuffix(".app") {
            key = bundle; name = URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent; iconPath = bundle
        } else if path.contains(".vscode/extensions/") || path.contains(".cursor/extensions/") {
            let app = path.contains(".cursor/") ? "Cursor" : "Visual Studio Code"
            key = "editor:\(app)"; name = app
            let candidate = "/Applications/\(app).app"
            iconPath = FileManager.default.fileExists(atPath: candidate) ? candidate : nil
        } else if path.hasSuffix("language_server_macos_arm") {
            key = "lsp"; name = "Code Intelligence (LSP)"; iconPath = nil
        } else if !path.isEmpty || !process.isEmpty {
            let value = path.isEmpty ? process : path
            key = value; name = (value as NSString).lastPathComponent; iconPath = value.hasPrefix("/") ? value : nil
        } else {
            key = "unidentified:\(source)"; name = "Unidentified · \(source.isEmpty ? "Local" : source)"; iconPath = nil
        }
    }

    var isAres: Bool {
        name == "Ares" || name == "clash-meta" || name == "com.herastudio.ares" || name == "com.ares.Ares"
    }
}

nonisolated enum ConnectionSnapshot {
    static func decode(_ data: Data) -> [Connection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["connections"] as? [[String: Any]] else { return [] }
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let m = row["metadata"] as? [String: Any] else { return nil }
            func text(_ key: String) -> String { (m[key] as? String) ?? (m[key] as? NSNumber)?.stringValue ?? "" }
            let metadata = ConnectionMetadata(network: text("network"), type: text("type"), sourceIP: text("sourceIP"), destinationIP: text("destinationIP"), sourcePort: text("sourcePort"), destinationPort: text("destinationPort"), host: text("host").isEmpty ? text("sniffHost") : text("host"), processPath: text("processPath"), process: text("process"), inboundIP: text("inboundIP"), inboundPort: text("inboundPort"))
            return Connection(id: id, metadata: metadata, upload: (row["upload"] as? NSNumber)?.int64Value ?? 0, download: (row["download"] as? NSNumber)?.int64Value ?? 0, start: date.date(from: row["start"] as? String ?? "") ?? Date(), chains: row["chains"] as? [String] ?? [], rule: row["rule"] as? String ?? "", rulePayload: row["rulePayload"] as? String ?? "")
        }
    }
}

nonisolated struct SocketOwner: Sendable {
    let pid: Int32
    let process: String
    let network: String
    let local: String
    let peer: String

    static func endpoint(_ host: String, _ port: String) -> String {
        let host = host.replacingOccurrences(of: "::ffff:", with: "")
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
    static func parse(_ text: String) -> [SocketOwner] {
        var pid: Int32 = 0, process = "", network = ""
        var result: [SocketOwner] = []
        for line in text.split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value) ?? 0; process = ""; network = ""
            case "c": process = value
            case "f": network = ""
            case "P": network = value.lowercased()
            case "n":
                let parts = value.components(separatedBy: "->")
                if pid > 0, parts.count == 2 { result.append(SocketOwner(pid: pid, process: process, network: network, local: parts[0], peer: parts[1])) }
            default: break
            }
        }
        return result
    }
    static func match(_ metadata: ConnectionMetadata, in owners: [SocketOwner]) -> SocketOwner? {
        let local = endpoint(metadata.sourceIP, metadata.sourcePort)
        let isTun = metadata.type.lowercased() == "tun"
        let peer = isTun ? endpoint(metadata.destinationIP, metadata.destinationPort) : endpoint(metadata.inboundIP ?? "", metadata.inboundPort ?? "")
        let matches = owners.filter { $0.network == metadata.network.lowercased() && $0.local == local && $0.peer == peer }
        guard let first = matches.first, Set(matches.map(\.pid)).count == 1 else { return nil }
        return first
    }
}
