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

/// In-page controls: the left is for scope and the right for search and actions.
/// Wrap at an actual fit boundary, including when an inspector is open.
struct WorkspaceControls<Scope: View, Actions: View>: View {
    var placeholder: String? = nil
    var search: Binding<String>? = nil
    @ViewBuilder var scope: () -> Scope
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.md) {
                scope().fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                searchField
                actionGroup
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                scope()
                HStack(spacing: DS.Space.md) {
                    searchField
                    Spacer(minLength: 0)
                    actionGroup
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                scope()
                searchField
                actionGroup
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .font(DS.Typography.secondary)
        .buttonStyle(.borderless)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var searchField: some View {
        if let placeholder, let search {
            WorkspaceSearch(placeholder: placeholder, text: search)
        }
    }

    private var actionGroup: some View {
        HStack(spacing: DS.Space.sm) { actions() }.fixedSize(horizontal: true, vertical: false)
    }
}

struct WorkspaceSearch: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(DS.Typography.metadata).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).focused($focused).accessibilityLabel(placeholder)
                .onExitCommand { if !text.isEmpty { text = "" } else { focused = false } }
            if !text.isEmpty {
                Button { text = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear search").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(DS.soft, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? DS.accent : DS.line, lineWidth: focused ? 1 : DS.hairline).allowsHitTesting(false) }
        .frame(minWidth: 124, idealWidth: 182, maxWidth: 200)
    }
}

struct WorkspaceAction: View {
    let title: String
    let symbol: String
    var primary = false
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) { Label(title, systemImage: symbol).labelStyle(.titleAndIcon) }
            .fixedSize().controlSize(.small)
        if primary { button.buttonStyle(.bordered) } else { button.buttonStyle(.borderless) }
    }
}

struct CollectionTools<Actions: View>: View {
    let placeholder: String
    @Binding var search: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        WorkspaceControls(placeholder: placeholder, search: $search, scope: { EmptyView() }, actions: actions)
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
