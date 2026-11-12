import Foundation

nonisolated enum ConfigurationValidationFailure: LocalizedError {
    case resourcesUnavailable
    var errorDescription: String? {
        "The subscription needs GeoIP or rule data that could not be downloaded. Check the network and try applying it again. The previous configuration was kept."
    }
    static func isResourceFailure(_ log: String) -> Bool {
        resourceKey(in: log) != nil
    }
    static func resourceKey(in log: String) -> String? {
        let text = log.lowercased()
        for (phrase, key) in [("can't download mmdb", "mmdb"), ("can't download geoip", "geoip"), ("can't download geosite", "geosite"), ("can't download asn", "asn")] {
            if text.contains(phrase) { return key }
        }
        // A stalled download may be terminated before the core prints its error.
        for (name, key) in [("mmdb", "mmdb"), ("geoip.dat", "geoip"), ("geosite.dat", "geosite"), ("asn.mmdb", "asn")] {
            if text.contains("can't find \(name), start download"),
               !text.contains("download \(name) finish") { return key }
        }
        return nil
    }
}
