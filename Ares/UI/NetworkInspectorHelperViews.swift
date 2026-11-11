import SwiftUI

// MARK: - Helpers

struct SectionView<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Typography.metadata.weight(.semibold))
                .foregroundColor(.secondary)

            content
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key + ":")
                .font(DS.Typography.metadata.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)

            Text(value)
                .font(DS.Typography.metadata.monospaced())
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundColor(.secondary)
            Text("Verify extension settings if content is missing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
