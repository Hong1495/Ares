import SwiftUI

struct SettingsTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        Picker("Settings category", selection: $selection) {
            ForEach(titles.indices, id: \.self) { index in
                Text(titles[index]).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: 520, alignment: .leading)
    }
}

struct SettingsSectionTitle: View {
    let title: String
    let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }
}

struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label.font(.system(size: 13))
            Spacer(minLength: 16)
            configuration.content.controlSize(.small)
        }
        .frame(minHeight: 28)
        .frame(maxWidth: .infinity)
    }
}
