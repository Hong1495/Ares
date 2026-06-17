import SwiftUI

struct AdvancedModeCard: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var clashViewModel: ClashViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Zone
            HStack(spacing: 12) {
                Image(systemName: "bolt.shield")
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundStyle(.primary)

                Text("Advanced Mode")
                    .font(.headline.weight(.medium))

                Spacer()
            }
            .frame(height: 24)
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // 2. Content Zone
            VStack(alignment: .leading, spacing: 12) {
                // TUN Toggle
                HStack {
                    Text("TUN Mode")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appState.tunEnabled },
                        set: { _ in appState.toggleTUN() }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .labelsHidden()
                    .disabled(clashViewModel.isToggling)
                }

                // MITM Toggle
                HStack {
                    Text("MITM Shield")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appState.mitmEnabled },
                        set: { _ in appState.toggleMITM() }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                    .labelsHidden()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 150)
        .cardStyle()
    }
}

// Merged IP Address Card showing both local and public IP
