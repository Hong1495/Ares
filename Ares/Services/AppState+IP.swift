import Foundation

extension AppState {
    /// Update shared IP info
    func updateIPInfo(ip: String, country: String?) {
        let changed = publicIP != ip
        publicIP = ip
        // Do not pair a newly observed IP with the previous exit country.
        if let newCountry = country {
            countryCode = newCountry
        } else if changed || ip == "Offline" {
            countryCode = nil
        }
    }
}
