import SwiftUI

struct TabRow: View {
    let tab: BrowserTab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "safari")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? "Untitled Tab" : tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                    .lineLimit(1)

                Text(tab.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if !tab.requests.isEmpty {
                Text("\(tab.requests.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                    .foregroundStyle(isSelected ? .white : .blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
