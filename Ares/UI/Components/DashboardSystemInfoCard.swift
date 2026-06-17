import SwiftUI

struct SystemInfoCard: View {
    @State private var architecture: String = "Unknown"
    @State private var osVersion: String = "Unknown"

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("System")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(osVersion)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                HStack {
                    Text("Arch") // Shortened to match space
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(architecture)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 150)
        .cardStyle()
        .task {
            await Task.yield()
            fetchSystemInfo()
        }
    }

    private func fetchSystemInfo() {
        // Get architecture
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        DispatchQueue.main.async {
            architecture = machine
            let version = ProcessInfo.processInfo.operatingSystemVersion
            osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
    }
}

/// Node Analysis Card - Concise stats
