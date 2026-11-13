import SwiftUI

/// Shared title metrics and tools for the small collection pages.
struct CollectionTitleToolbar: ToolbarContent {
    let title: String
    let count: Int?
    let unit: String
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 24) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let count { HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(count))
                        .font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .ignore).accessibilityLabel("\(count) \(unit)") }
            }.padding(.leading, 16)
        }.aresUnframed()
    }
}

struct CollectionTools<Actions: View>: View {
    let placeholder: String
    @Binding var search: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Spacer(minLength: DS.Space.sm)
            TextField(placeholder, text: $search)
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .frame(minWidth: 130, idealWidth: 200, maxWidth: 200)
            HStack(spacing: DS.Space.xs) { actions() }
                .font(.system(size: 13, weight: .regular))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.pageTop)
        .padding(.bottom, DS.Space.md)
    }
}

struct SubscriptionHeading: View {
    let name: String
    let source: String
    let remote: Bool
    let selected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: remote ? "cloud" : "doc")
                .font(.system(size: 13, weight: .regular)).symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary).frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(source).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(DS.accent)
                    .accessibilityLabel("Selected subscription")
            }
        }
    }
}

struct SubscriptionSurface: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).fill(selected ? DS.accent.opacity(0.06) : .clear).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(selected ? 0.23 : 0.16), lineWidth: 1).allowsHitTesting(false))
    }
}
