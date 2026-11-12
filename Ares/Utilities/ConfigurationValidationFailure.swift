import Foundation

nonisolated enum ConfigurationValidationFailure: LocalizedError {
    case resourcesUnavailable
    var errorDescription: String? {
        "The subscription needs GeoIP or rule data that could not be downloaded. Check the network and try applying it again. The previous configuration was kept."
    }
    static func isResourceFailure(_ log: String) -> Bool {
        let text = log.lowercased()
        return ["can't download mmdb", "can't download geoip", "can't download geosite"].contains { text.contains($0) }
    }
}
