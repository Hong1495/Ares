import SwiftUI
import AppKit

/// Presentation only: safe to compile into the isolated preview executable.
struct WorkspaceDestination: Identifiable {
    let id: String
    let title: String
    let icon: String
    let section: String
}

struct WorkspaceSidebar: View {
    let destinations: [WorkspaceDestination]
    @Binding var selection: String
    let status: String
    let detail: String
    let statusKind: DSStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: [String] {
        destinations.reduce(into: []) { if !$0.contains($1.section) { $0.append($1.section) } }
    }

    private var selected: Binding<String?> {
        Binding(get: { selection }, set: { if let value = $0 { selection = value } })
    }

    var body: some View {
        List(selection: selected) {
            ForEach(sections.filter { $0 != "Preferences" }, id: \.self) { section in
                Section(section) {
                    ForEach(destinations.filter { $0.section == section }) { destination in
                        Label(destination.title, systemImage: destination.icon)
                            .font(DS.Typography.body)
                            .labelStyle(.titleAndIcon)
                            .tag(destination.id)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(destinations.filter { $0.section == "Preferences" }) { destination in
                    Button { selection = destination.id } label: {
                        Label(destination.title, systemImage: destination.icon)
                            .font(DS.Typography.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            .background(selection == destination.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    Circle().fill(statusKind.color).frame(width: 5, height: 5)
                    Text(status).lineLimit(1)
                }
                .font(DS.Typography.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
                .help(detail)
            }.padding(10)
        }
    }
}

struct DSQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct DSPageHeading: View {
    let title: String
    let subtitle: String
    var eyebrow: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow).font(DS.Typography.caption.weight(.medium)).tracking(1.8).foregroundStyle(DS.accent)
            }
            Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.7).foregroundStyle(DS.ink)
            Text(subtitle).font(DS.Typography.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DSPageTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(titles.indices, id: \.self) { index in
                Button { selection = index } label: {
                    Text(titles[index])
                        .font(DS.Typography.secondary.weight(selection == index ? .semibold : .regular))
                        .foregroundStyle(selection == index ? DS.ink : Color.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(selection == index ? DS.surface : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(selection == index ? DS.line : .clear, lineWidth: DS.hairline))
                }
                .buttonStyle(DSQuietButtonStyle())
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// Keep system toolbar sizing and hit targets without the glass button outlines.
extension ToolbarContent {
    @ToolbarContentBuilder
    func aresUnframed() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct AresSidebarToolbar: ToolbarContent {
    @Binding var visibility: NavigationSplitViewVisibility

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            DefaultToolbarItem(kind: .sidebarToggle)
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                Button {
                    visibility = visibility == .detailOnly ? .all : .detailOnly
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Show or hide sidebar")
            }
        }
    }
}

/// SwiftUI's native sidebar item keeps its AppKit border on macOS 27 even when
/// shared backgrounds are hidden. Preserve native placement and toggle behavior.
struct SidebarToolbarAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarToolbarAppearanceView {
        SidebarToolbarAppearanceView()
    }

    func updateNSView(_ view: SidebarToolbarAppearanceView, context: Context) {
        view.scheduleUpdate()
    }
}

final class SidebarToolbarAppearanceView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleUpdate()
    }

    override func layout() {
        super.layout()
        scheduleUpdate()
    }

    func scheduleUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let toolbar = self?.window?.toolbar else { return }
            for item in toolbar.items where item.itemIdentifier == .toggleSidebar || item.itemIdentifier.rawValue == "com.apple.SwiftUI.navigationSplitView.toggleSidebar" {
                item.isBordered = false
                if !(item.view is NSButton) {
                    let button = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")!, target: nil, action: #selector(NSSplitViewController.toggleSidebar(_:)))
                    button.isBordered = false
                    button.imagePosition = .imageOnly
                    button.setButtonType(.momentaryChange)
                    button.frame.size = NSSize(width: 32, height: 32)
                    button.toolTip = "Show or hide sidebar"
                    item.view = button
                }
                (item.view as? NSButton)?.isBordered = false
            }
        }
    }
}
