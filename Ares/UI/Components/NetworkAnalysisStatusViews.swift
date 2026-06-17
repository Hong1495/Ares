import SwiftUI

struct StatusIcon: View {
    let req: BrowserRequest

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            if let code = req.statusCode {
                Text("\(code)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(code >= 400 ? .red : .secondary)
            }
        }
    }

    private var color: Color {
        switch req.status {
        case .pending, .active: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}

struct TypeBadge: View {
    let type: String

    var body: some View {
        Text(type.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .foregroundStyle(.secondary)
            .cornerRadius(3)
    }
}

// MARK: - Inspector & Payload Views
