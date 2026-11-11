import SwiftUI
import AppKit

// MARK: - Tokens

/// Single source of truth for spacing, radii and semantic color.
/// Every view in Ares should pull from here instead of hard-coding numbers.
enum DS {
    /// Native macOS styles: body 13pt, callout 12pt, subheadline 11pt,
    /// caption 10pt. Keep SF Pro and system metrics; use monospaced only for data.
    enum Typography {
        static let body: Font = .body
        static let secondary: Font = .callout
        static let metadata: Font = .subheadline
        static let caption: Font = .caption
        static let title: Font = .title3
        static let sectionTitle: Font = .title2
        static let metric: Font = .system(.title, design: .rounded, weight: .medium)
    }


    static let canvas = Color.adaptive(light: NSColor(rgb: 0xF7F7F9), dark: NSColor(rgb: 0x222327))
    static let surface = Color.adaptive(light: NSColor(rgb: 0xFFFFFF), dark: NSColor(rgb: 0x2C2D32))
    static let sidebar = Color.adaptive(light: NSColor(rgb: 0xEEEEF2), dark: NSColor(rgb: 0x28292E))
    static let ink = Color.adaptive(light: NSColor(rgb: 0x27282D), dark: NSColor(rgb: 0xF1F1F4))
    static let accent = Color.adaptive(light: NSColor(rgb: 0x3E6DAD), dark: NSColor(rgb: 0x91B8ED))
    static let line = Color.primary.opacity(0.075)
    static let soft = Color.primary.opacity(0.035)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 8
        static let tile: CGFloat = 9
        static let card: CGFloat = 16
        static let hero: CGFloat = 22
        static let capsule: CGFloat = 999
    }

    /// Hairline used for every surface border in the app.
    static let hairline: CGFloat = 0.5
}

// MARK: - Color

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {

    /// A color that resolves differently in light and dark appearance.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }

    // MARK: Data series
    // Validated pair (dataviz palette): CVD ΔE 24.7, normal-vision ΔE 33.6.
    // Download = blue slot 1, Upload = orange slot 2.

    static let seriesDown = Color.adaptive(light: NSColor(rgb: 0x2A78D6), dark: NSColor(rgb: 0x3987E5))
    static let seriesUp = Color.adaptive(light: NSColor(rgb: 0xEB6834), dark: NSColor(rgb: 0xD95926))

    // MARK: Status
    // Reserved for state only — never reused as a chart series.

    static let statusGood = Color.adaptive(light: NSColor(rgb: 0x12874C), dark: NSColor(rgb: 0x3DDC7F))
    static let statusWarn = Color.adaptive(light: NSColor(rgb: 0xB8690A), dark: NSColor(rgb: 0xFFB340))
    static let statusBad = Color.adaptive(light: NSColor(rgb: 0xC0281F), dark: NSColor(rgb: 0xFF6B60))
    static let statusIdle = Color.adaptive(light: NSColor(rgb: 0x8A8A8E), dark: NSColor(rgb: 0x9A9AA0))

    /// Latency quality ramp used by every latency readout in the app.
    static func latency(_ ms: Int?) -> Color {
        guard let ms else { return .statusIdle }
        if ms < 200 { return .statusGood }
        if ms < 500 { return .statusWarn }
        return .statusBad
    }
}

// MARK: - Status

enum DSStatus {
    case good
    case warning
    case critical
    case idle

    var color: Color {
        switch self {
        case .good: return .statusGood
        case .warning: return .statusWarn
        case .critical: return .statusBad
        case .idle: return .statusIdle
        }
    }

    var symbol: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .idle: return "circle.dashed"
        }
    }
}

// MARK: - Surfaces

struct DSSurfaceBackground: View {
    var radius: CGFloat = DS.Radius.card

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DS.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.line, lineWidth: DS.hairline)
            )
            .shadow(color: .black.opacity(0.015), radius: 10, x: 0, y: 3)
    }
}

private struct DSFlatSurfacesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var flatSurfaces: Bool {
        get { self[DSFlatSurfacesKey.self] }
        set { self[DSFlatSurfacesKey.self] = newValue }
    }
}

/// Standard content card. Content sizes itself — never force a fixed height.
struct DSCard<Content: View>: View {
    @Environment(\.flatSurfaces) private var flat
    var padding: CGFloat
    var spacing: CGFloat
    var radius: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = DS.Space.lg,
        spacing: CGFloat = DS.Space.md,
        radius: CGFloat = DS.Radius.card,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.spacing = spacing
        self.radius = radius
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { if !flat { DSSurfaceBackground(radius: radius) } }
    }
}

// MARK: - Card header

struct DSCardHeader<Trailing: View>: View {
    @Environment(\.flatSurfaces) private var flat
    let title: String
    var subtitle: String?
    let icon: String
    var tint: Color
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        icon: String,
        subtitle: String? = nil,
        tint: Color = .accentColor,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DS.Space.sm + 2) {
            Image(systemName: icon)
                .font(DS.Typography.secondary.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(flat ? DS.Typography.secondary : DS.Typography.body.weight(.semibold))
                    .foregroundStyle(flat ? .secondary : .primary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Space.sm)

            trailing()
        }
    }
}

extension DSCardHeader where Trailing == EmptyView {
    init(_ title: String, icon: String, subtitle: String? = nil, tint: Color = .accentColor) {
        self.init(title, icon: icon, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

// MARK: - Metrics

struct DSMetric: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typography.metadata)
                .foregroundStyle(.secondary)

            Text(value)
                .font(DS.Typography.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let detail {
                Text(detail)
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pill

struct DSStatusPill: View {
    let text: String
    var status: DSStatus = .idle

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(DS.Typography.metadata.weight(.semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(status.color.opacity(0.12)))
        
    }
}

struct DSTag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(DS.Typography.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.12)))
    }
}

// MARK: - Rows

struct DSToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = .accentColor
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: DS.Space.sm + 2) {
            Image(systemName: icon)
                .font(DS.Typography.metadata.weight(.semibold))
                .foregroundStyle(isOn ? tint : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill((isOn ? tint : Color.secondary).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Typography.body.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Space.sm)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(tint)
        }
        .contentShape(Rectangle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

struct DSKeyValueRow: View {
    let label: String
    let value: String
    var valueTint: Color = .secondary
    var monospaced: Bool = true

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(label)
                .font(DS.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: DS.Space.sm)
            Text(value)
                .font((monospaced ? DS.Typography.metadata.monospaced() : DS.Typography.metadata).weight(.medium))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

