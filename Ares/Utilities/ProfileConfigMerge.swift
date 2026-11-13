import Foundation

/// Field ownership for the effective document. Unlisted subscription fields are inherited.
nonisolated enum ProfileConfigMerge {
    static let runtimePaths: [[String]] = [
        ["mixed-port"], ["socks-port"], ["port"], ["mode"], ["log-level"],
        ["allow-lan"], ["ipv6"], ["external-controller"], ["secret"],
        ["find-process-mode"], ["tun", "enable"],
        ["profile", "store-selected"], ["profile", "store-fake-ip"]
    ]

    static let preferencePaths: [String: [String]] = [
        DefaultsKeys.dnsServers: ["dns", "nameserver"],
        DefaultsKeys.ipv6: ["dns", "ipv6"],
        DefaultsKeys.tunStack: ["tun", "stack"],
        DefaultsKeys.tunMTU: ["tun", "mtu"],
        DefaultsKeys.tunDevice: ["tun", "device"],
        DefaultsKeys.tunAutoRoute: ["tun", "auto-route"],
        DefaultsKeys.tunAutoDetectInterface: ["tun", "auto-detect-interface"],
        DefaultsKeys.keepAliveInterval: ["keep-alive-interval"],
        DefaultsKeys.udpTimeout: ["udp-timeout"]
    ]

    static var inheritablePaths: [String: [String]] {
        preferencePaths.filter { $0.key != DefaultsKeys.ipv6 }
    }

    static func overridePaths(defaults: UserDefaults, tunEnabled: Bool) -> [[String]] {
        var paths = runtimePaths
        for key in preferencePaths.keys.sorted() where defaults.object(forKey: key) != nil {
            let path = preferencePaths[key]!
            if path.first != "tun" || tunEnabled { paths.append(path) }
        }
        // TUN requires the internal resolver, but its policies remain inherited.
        if tunEnabled { paths.append(["dns", "enable"]) }
        return paths
    }
}

/// Saves only edited controls; a rollback restores missing keys as missing, not as UI defaults.
nonisolated struct NetworkPreferenceChange {
    let values: [String: Any]
    let previous: [String: Any]
    let removals: Set<String>

    init(proposed: [String: Any], displayed: [String: Any], defaults: UserDefaults, removals: Set<String> = [], forced: Set<String> = []) {
        self.removals = removals
        values = proposed.filter { key, value in
            if removals.contains(key) { return false }
            if forced.contains(key) { return true }
            guard let old = displayed[key] else { return true }
            return !NSDictionary(dictionary: [key: value]).isEqual(to: [key: old])
        }
        previous = Set(values.keys).union(removals).reduce(into: [:]) { result, key in
            if let value = defaults.object(forKey: key) { result[key] = value }
        }
    }

    func apply(to defaults: UserDefaults) {
        removals.forEach { defaults.removeObject(forKey: $0) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
    }

    func restore(in defaults: UserDefaults) {
        for key in Set(values.keys).union(removals) {
            if let value = previous[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
}
