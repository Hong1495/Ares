import SwiftUI

/// Subscription labels are hints, never geolocation results.
nonisolated enum ProxyCountryLabel {
    static func code(in name: String) -> String? {
        for character in name {
            let scalars = Array(character.unicodeScalars)
            if scalars.count == 2, scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) {
                let code = String(String.UnicodeScalarView(scalars.compactMap { UnicodeScalar($0.value - 0x1F1E6 + 65) }))
                if Locale.Region.isoRegions.contains(where: { $0.identifier == code }) { return code }
            }
        }
        let tokens = Set(name.uppercased().split { !$0.isLetter }.map(String.init))
        for (code, aliases) in [
            ("US", ["United States", "美国", "洛杉矶", "Los Angeles"]),
            ("JP", ["Japan", "日本", "东京", "Tokyo"]),
            ("SG", ["Singapore", "新加坡"]), ("HK", ["Hong Kong", "香港"]),
            ("TW", ["Taiwan", "台湾"]), ("GB", ["United Kingdom", "英国", "London"]),
            ("DE", ["Germany", "德国"]), ("FR", ["France", "法国"]),
            ("NL", ["Netherlands", "荷兰"]), ("MY", ["Malaysia", "马来西亚"]),
            ("KR", ["South Korea", "韩国"]), ("CA", ["Canada", "加拿大"]),
            ("AU", ["Australia", "澳大利亚"])
        ] {
            if tokens.contains(code) || aliases.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return code }
        }
        return nil
    }
}

struct ProxiesTitleToolbar: ToolbarContent {
    let count: Int
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 24) {
                Text("Proxies").font(.system(size: 13, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(count)).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("Nodes").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .ignore).accessibilityLabel("\(count) nodes")
            }.padding(.leading, 16)
        }.aresUnframed()
    }
}

nonisolated enum ProxyNodeOrder {
    static func sorted(_ names: [String], delay: (String) -> Int?) -> [String] {
        let entries = names.enumerated().map { index, name in
            (name: name, delay: delay(name).flatMap { $0 > 0 ? $0 : nil } ?? Int.max,
             country: ProxyCountryLabel.code(in: name) ?? "~", index: index)
        }
        return entries.sorted {
            if $0.country != $1.country { return $0.country < $1.country }
            if $0.delay != $1.delay { return $0.delay < $1.delay }
            return $0.index < $1.index
        }.map(\.name)
    }
}

/// Matches the dashboard's monochrome symbol size and weight.
struct ProxyLatencySymbol: View {
    var body: some View {
        Image(systemName: "bolt")
            .font(.system(size: 13, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}
