import SwiftUI

/// Shared by live proxy groups and the service-free preview.
struct SimpleProxyButton: View {
    let name: String
    let isSelected: Bool
    let delay: Int?
    let isTesting: Bool
    var canSelect: Bool = true
    var canTest: Bool = true
    let onSelect: () -> Void
    let onTest: () -> Void
    @State private var hovering = false
    @State private var metricWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var latencyDescription: String {
        if isTesting { return "Testing" }
        guard let delay else { return "Not measured" }
        return delay > 0 ? "\(delay) milliseconds" : "Unavailable"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? DS.accent : Color.secondary.opacity(0.5))
                    Text(name).font(DS.Typography.secondary.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSelect)
            .help(canSelect ? "Select \(name)" : "Selection is unavailable while busy or in a load-balancing group")
            .accessibilityLabel("Select \(name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Button(action: onTest) {
                ProxyLatencySymbol().frame(width: 22, height: 22)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(!canTest || isTesting)
            .help(canTest ? "Test latency for \(name)" : "Connect to test latency")
            .accessibilityLabel("Test latency for \(name)")
        }
        .padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 12)
        .background(isSelected ? DS.accent.opacity(0.10) : Color.primary.opacity(hovering ? 0.065 : 0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(isSelected ? 0.23 : 0.16), lineWidth: 1)
                .mask {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Color.black.frame(width: 14)
                            Color.clear.frame(width: metricWidth)
                            Color.black
                        }.frame(height: 2)
                        Color.black
                    }
                }
        }
        .overlay(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ProxyCountryLabel.code(in: name) ?? "—")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .help("Region from the subscription name; not a verified exit location")
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if isTesting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(delay.flatMap { $0 > 0 ? String($0) : nil } ?? "—")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit().foregroundStyle(Color.latency(delay))
                    }
                    Text("ms").font(.system(size: 10)).foregroundStyle(.secondary)
                }.help(latencyDescription)
            }
            .padding(.horizontal, 6)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { metricWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in metricWidth = width }
                }
            }
            .offset(x: 14, y: -11)
        }
        .padding(.top, 11)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
    }
}

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
