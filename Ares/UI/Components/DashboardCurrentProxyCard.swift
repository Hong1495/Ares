import SwiftUI

struct CurrentProxyCard: View {
    @EnvironmentObject var clashController: ClashController
    @EnvironmentObject var clashViewModel: ClashViewModel
    @EnvironmentObject var appState: AppState

    // Auto-refresh latency
    @State private var latencies: [String: Int] = [:]

    // Display groups based on mode
    var displayGroups: [ProxyGroup] {
        switch appState.currentMode {
        case .global:
            return clashController.proxyGroups.filter { $0.name == "GLOBAL" }
        case .direct:
            return []
        case .rule:
            // Smart select the main proxy group
            let allGroups = clashController.proxyGroups

            // 1. Try exact match for common standards
            if let exact = allGroups.first(where: { $0.name == "🚀 节点选择" }) { return [exact] }
            if let exact = allGroups.first(where: { $0.name == "Proxy" }) { return [exact] }
            if let exact = allGroups.first(where: { $0.name == "PROXY" }) { return [exact] }

            // 2. Try partial match
            if let partial = allGroups.first(where: { $0.name.contains("节点") && $0.type == "Selector" }) { return [partial] }
            if let partial = allGroups.first(where: { $0.name.contains("Proxy") && $0.type == "Selector" }) { return [partial] }

            // 3. Fallback: First non-GLOBAL selector
            if let fallback = allGroups.first(where: { $0.type == "Selector" && $0.name != "GLOBAL" }) { return [fallback] }

            return []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Current Proxy")
                    .font(.headline.weight(.medium))

                Spacer()
                // Mode indicator
                Text(appState.currentMode.rawValue.capitalized)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(modeColor.opacity(0.15))
                    .foregroundStyle(modeColor)
                    .cornerRadius(6)
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack {
                if appState.currentMode == .direct {
                    // Direct mode
                    HStack {
                        Image(systemName: "arrow.forward.circle")
                            .foregroundStyle(.green)
                        Text("Direct Connection")
                            .font(.subheadline)
                    }
                } else if displayGroups.isEmpty {
                     Text("No proxy configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Show groups with latency on right
                    ForEach(displayGroups) { group in
                        HStack(alignment: .center, spacing: 16) {
                            // Left: Group names
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if let current = group.now {
                                    Text(current)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            // Right: Latency in large font
                            if let current = group.now, let ms = latencies[current] {
                                HStack(alignment: .lastTextBaseline, spacing: 2) {
                                    Text("\(ms)")
                                        .font(.system(size: 40, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text("ms")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .opacity(0.8)
                                }
                                .foregroundStyle(latencyColor(ms))
                            } else {
                                HStack(alignment: .lastTextBaseline, spacing: 2) {
                                    Text("--")
                                        .font(.system(size: 40, weight: .bold, design: .rounded))
                                    Text("ms")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .opacity(0.6)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 150)
        .cardStyle()
        .task {
            // Wait for Clash to be fully ready before testing
            while !clashViewModel.isRunning || clashViewModel.isToggling {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            // Additional wait for core stabilization
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await updateLatencies()

            // Periodic update
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                if clashViewModel.isRunning && !clashViewModel.isToggling {
                    await updateLatencies()
                }
            }
        }
    }

    private func updateLatencies() async {
        for group in displayGroups {
            if let current = group.now {
                // Skip if we already tested recently (< 5s)? No, auto-refresh is explicit.
                do {
                    let ms = try await clashController.testProxyDelay(name: current, timeout: 2000)
                    withAnimation {
                        latencies[current] = ms
                    }
                } catch {
                    // ignore
                }
            }
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 200 { return .green }
        if ms < 500 { return .orange }
        return .red
    }

    private var modeColor: Color {
        switch appState.currentMode {
        case .rule: return .blue
        case .global: return .orange
        case .direct: return .green
        }
    }

    private func groupIcon(for type: String) -> String {
        switch type {
        case "Selector": return "checkmark.circle"
        case "URLTest": return "speedometer"
        case "Fallback": return "arrow.triangle.2.circlepath"
        default: return "server.rack"
        }
    }
}

// Advanced Mode Card - Merged TUN and MITM Toggles
