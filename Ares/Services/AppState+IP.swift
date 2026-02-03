import Foundation

extension AppState {
    /// Update shared IP info
    func updateIPInfo(ip: String, country: String?) {
        publicIP = ip
        // Only update country if it's not nil, or if we are explicitly clearing it (e.g. "Offline")
        if let newCountry = country {
            countryCode = newCountry
        } else if ip == "Offline" {
            countryCode = nil
        }
    }
}
