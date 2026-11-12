import Foundation
import CryptoKit

/// Prepares geodata before validation. It never starts a listener or changes routing.
actor GeoResourceService {
    static let shared = GeoResourceService()

    struct Resource {
        let key: String
        let filename: String
        let upstreamName: String
        let aliases: [String]
    }
    static let resources = [
        Resource(key: "mmdb", filename: "geoip.metadb", upstreamName: "geoip.metadb", aliases: ["geoip.metadb", "Country.mmdb", "country.mmdb", "geoip.db"]),
        Resource(key: "geoip", filename: "GeoIP.dat", upstreamName: "geoip.dat", aliases: ["GeoIP.dat", "geoip.dat"]),
        Resource(key: "geosite", filename: "GeoSite.dat", upstreamName: "geosite.dat", aliases: ["GeoSite.dat", "geosite.dat"]),
        Resource(key: "asn", filename: "ASN.mmdb", upstreamName: "GeoLite2-ASN.mmdb", aliases: ["ASN.mmdb"])
    ]

    private let cache: URL
    private let direct: URLSession
    init(cacheDirectory: URL? = nil) {
        cache = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ares/GeoData")
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        direct = URLSession(configuration: config)
    }

    private func source(_ resource: Resource, overrides: [String: String]) -> String {
        overrides[resource.key] ?? "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/\(resource.upstreamName)"
    }

    private func cached(_ resource: Resource, overrides: [String: String]) -> URL {
        let hash = SHA256.hash(data: Data(source(resource, overrides: overrides).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return cache.appendingPathComponent(hash).appendingPathComponent(resource.filename)
    }

    func prepare(directory: URL, overrides: [String: String]) throws {
        let fm = FileManager.default
        for resource in Self.resources {
            // Preserve an existing runtime database. The core performs format validation.
            if resource.aliases.contains(where: { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }) { continue }
            let saved = cached(resource, overrides: overrides)
            if fm.fileExists(atPath: saved.path) {
                try fm.copyItem(at: saved, to: directory.appendingPathComponent(resource.filename))
            }
        }
    }

    func recover(log: String, directory: URL, overrides: [String: String]) async throws -> Bool {
        guard let key = ConfigurationValidationFailure.resourceKey(in: log),
              let resource = Self.resources.first(where: { $0.key == key }) else { return false }
        var sources = [source(resource, overrides: overrides)]
        // Only mirror the known default dataset; custom sources retain their semantics.
        if overrides[resource.key] == nil {
            sources.insert("https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/\(resource.upstreamName)", at: 0)
        }
        for address in sources {
            guard let url = URL(string: address), url.scheme == "https" || url.scheme == "http" else { continue }
            for session in [URLSession.shared, direct] {
                try Task.checkCancellation()
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          data.count > 1024, data.count < 100 * 1024 * 1024,
                          !(http.mimeType?.contains("text/html") ?? false) else { continue }
                    // The subsequent full core validation checks database format and rules.
                    for alias in resource.aliases {
                        let file = directory.appendingPathComponent(alias)
                        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                    }
                    try data.write(to: directory.appendingPathComponent(resource.filename), options: .atomic)
                    return true
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
            }
        }
        throw ConfigurationValidationFailure.resourcesUnavailable
    }

    /// Cache only after the complete configuration passed core validation.
    func remember(directory: URL, overrides: [String: String]) {
        let fm = FileManager.default
        for resource in Self.resources {
            guard let file = resource.aliases.map({ directory.appendingPathComponent($0) })
                .first(where: { fm.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: file), !data.isEmpty else { continue }
            let saved = cached(resource, overrides: overrides)
            try? fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: saved, options: .atomic)
        }
    }
}
