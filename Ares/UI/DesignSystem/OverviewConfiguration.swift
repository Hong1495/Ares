import SwiftUI

/// An empty snapshot represents a known zero; nil means the data was not read.
struct OverviewConfiguration {
    struct Resources {
        let nodes: Int
        let providers: Int
        let local: Int
        var total: Int { nodes + providers }
    }
    struct Devices {
        struct Live { let active: Int; let connections: Int }
        let enabled: Int
        let disabled: Int
        let live: Live?
    }
    struct Route {
        let application: String
        let target: String
    }
    struct Scenes {
        let names: [String]
        let automation: Automation
    }
    enum Automation {
        case off, paused, on
        var title: String {
            switch self { case .off: "Automation off"; case .paused: "Automation paused"; case .on: "Automation on" }
        }
        var symbol: String {
            switch self { case .off: "bolt.slash"; case .paused: "pause.circle"; case .on: "bolt" }
        }
        var tint: Color {
            switch self { case .off: .secondary; case .paused: .statusWarn; case .on: .statusGood }
        }
    }
    enum Section: String, CaseIterable {
        case resources = "Resources", devices = "Devices", applications = "Applications", policies = "Policies", scenes = "Scenes"
        var unit: String {
            switch self { case .resources: "resources"; case .devices: "configured"; case .applications: "local rules"; case .policies: "groups"; case .scenes: "saved" }
        }
    }
    var resources: Resources?
    var devices: Devices?
    var applications: [Route]?
    var policies: [String: Int]?
    var scenes: Scenes?

    func count(for section: Section) -> Int? {
        switch section {
        case .resources: resources?.total
        case .devices: devices.map { $0.enabled + $0.disabled }
        case .applications: applications?.count
        case .policies: policies?.values.reduce(0, +)
        case .scenes: scenes?.names.count
        }
    }
}

struct OverviewConfigurationGraphic: View {
    let section: OverviewConfiguration.Section
    let configuration: OverviewConfiguration
    private let previewLimit = 3
    private let quiet = Color.secondary.opacity(0.36)

    var body: some View {
        Group {
            switch section {
            case .resources:
                if let data = configuration.resources { resources(data) } else { unavailable }
            case .devices:
                if let data = configuration.devices { devices(data) } else { unavailable }
            case .applications:
                if let data = configuration.applications { applications(data) } else { unavailable }
            case .policies:
                if let data = configuration.policies { policies(data) } else { unavailable }
            case .scenes:
                if let data = configuration.scenes { scenes(data) } else { unavailable }
            }
        }.frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
    }

    private var unavailable: some View { placeholder("Unavailable", icon: "minus.circle") }

    private func resources(_ data: OverviewConfiguration.Resources) -> some View {
        VStack(spacing: 12) {
            composition(data.nodes, data.providers, labels: ("Nodes", "Providers"))
            composition(data.local, data.total - data.local, labels: ("Local", "Inherited"))
        }.help("Saved resource definitions in the current workspace")
    }

    private func composition(_ first: Int, _ second: Int, labels: (String, String)) -> some View {
        let total = first + second
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                Capsule().fill(total > 0 ? quiet : DS.line)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DS.accent.opacity(0.75))
                            .frame(width: total > 0 ? geometry.size.width * CGFloat(first) / CGFloat(total) : 0)
                    }.clipShape(Capsule())
            }.frame(height: 5).accessibilityHidden(true)
            HStack {
                legend(labels.0, value: first, tint: DS.accent.opacity(0.75))
                Spacer(minLength: 4)
                legend(labels.1, value: second, tint: quiet)
            }
        }.accessibilityElement(children: .combine)
    }

    private func legend(_ title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            number(value)
            Text(title).foregroundStyle(.secondary)
        }.font(DS.Typography.metadata)
    }

    private func devices(_ data: OverviewConfiguration.Devices) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 0) {
                deviceValue("Enabled", icon: "checkmark.circle", value: data.enabled, color: data.enabled > 0 ? .statusGood : .secondary)
                Divider().frame(height: 20)
                deviceValue("Disabled", icon: "minus.circle", value: data.disabled, color: .secondary)
            }.padding(.vertical, 7)
                .background(DS.soft, in: RoundedRectangle(cornerRadius: DS.Radius.control))
            HStack(spacing: 5) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle((data.live?.active ?? 0) > 0 ? Color.statusGood : .secondary)
                    .accessibilityLabel("Live")
                number(data.live?.active)
                Text("active").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                number(data.live?.connections)
                Text("connections").foregroundStyle(.secondary)
            }.font(DS.Typography.metadata).accessibilityElement(children: .combine)
                .help(data.live == nil ? "Live connection counts are unavailable" : "Current connections matched to saved device listeners")
        }
    }

    private func deviceValue(_ title: String, icon: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
                number(value)
            }.font(DS.Typography.body)
            Text(title).font(DS.Typography.metadata).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func applications(_ routes: [OverviewConfiguration.Route]) -> some View {
        if routes.isEmpty {
            placeholder("No local rules", icon: "arrow.triangle.branch")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(routes.prefix(previewLimit).indices, id: \.self) { index in
                    let route = routes[index]
                    HStack(spacing: 6) {
                        Image(systemName: "app").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(route.application).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                        Text(route.target).lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(DS.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.font(DS.Typography.metadata)
                        .help("\(route.application) → \(route.target)")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(route.application) routes to \(route.target)")
                }
                more(routes.count)
            }
        }
    }

    @ViewBuilder private func policies(_ counts: [String: Int]) -> some View {
        let total = counts.values.reduce(0, +)
        let known = [("select", "Manual"), ("url-test", "Latency"), ("fallback", "Failover"), ("load-balance", "Balanced")]
        let recognized = known.map { ($0.1, counts[$0.0, default: 0]) }
        let other = total - recognized.reduce(0) { $0 + $1.1 }
        let lanes = (recognized + [("Other", other)]).filter { $0.1 > 0 }
        if total == 0 {
            placeholder("No policy groups", icon: "slider.horizontal.3")
        } else {
            VStack(spacing: 6) {
                ForEach(lanes.indices, id: \.self) { index in
                    let (label, count) = lanes[index]
                    HStack(spacing: 7) {
                        Text(label).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                        GeometryReader { geometry in
                            Capsule().fill(DS.line).frame(height: 1).frame(maxHeight: .infinity)
                            Circle().fill(DS.accent).frame(width: 7, height: 7)
                                .position(x: 3.5 + max(0, geometry.size.width - 7) * CGFloat(count) / CGFloat(total), y: geometry.size.height / 2)
                        }.frame(height: 9).accessibilityHidden(true)
                        number(count).frame(minWidth: 18, alignment: .trailing)
                    }.font(DS.Typography.metadata).accessibilityElement(children: .combine)
                }
            }.help("Dot position shows each type’s share of saved groups, from 0 to 100%")
        }
    }

    private func scenes(_ data: OverviewConfiguration.Scenes) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if data.names.isEmpty {
                placeholder("No saved scenes", icon: "square.3.layers.3d")
            } else {
                VStack(spacing: 2) {
                    ForEach(data.names.prefix(previewLimit).indices, id: \.self) { index in
                        HStack(spacing: 7) {
                            Image(systemName: "square.2.layers.3d").foregroundStyle(DS.accent).accessibilityHidden(true)
                            Text(data.names[index]).lineLimit(1).help(data.names[index])
                            Spacer(minLength: 0)
                        }.font(DS.Typography.metadata).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.soft, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            HStack {
                Label(data.automation.title, systemImage: data.automation.symbol).foregroundStyle(data.automation.tint)
                Spacer(minLength: 0)
                more(data.names.count)
            }.font(DS.Typography.metadata)
        }
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map { $0.formatted() } ?? "—").fontWeight(.medium).monospacedDigit()
    }
    @ViewBuilder private func more(_ count: Int) -> some View {
        if count > previewLimit {
            Text("+\(count - previewLimit) more").font(DS.Typography.metadata).foregroundStyle(.secondary)
        }
    }
    private func placeholder(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(title)
        }.font(DS.Typography.metadata).foregroundStyle(.secondary).frame(minHeight: 28, alignment: .leading)
    }
}
