import SwiftUI

struct InspectorView: View {
    let request: BrowserRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(request.url)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if request.hitCount > 1 {
                    Text("\(request.hitCount) hits")
                        .font(DS.Typography.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailSection(title: "Overview") {
                        DetailRow(label: "URL", value: request.url)
                        DetailRow(label: "Remote Address", value: request.remoteAddress ?? "Unknown")
                        DetailRow(label: "Method", value: request.method)
                        DetailRow(label: "Status", value: "\(request.status.rawValue.uppercased()) \(request.statusCode.map { "(\($0))" } ?? "")")
                    }

                    if let requestHeaders = request.requestHeaders, !requestHeaders.isEmpty {
                        DetailSection(title: "Request Headers") {
                            HeaderListView(headers: requestHeaders)
                        }
                    }

                    if let responseHeaders = request.responseHeaders, !responseHeaders.isEmpty {
                        DetailSection(title: "Response Headers") {
                            HeaderListView(headers: responseHeaders)
                        }
                    }

                    DetailSection(title: "Timing") {
                        DetailRow(label: "Started", value: formatFullTime(request.timestamp))
                        if let dur = request.duration {
                            DetailRow(label: "Duration", value: String(format: "%.3f s", dur))
                            WaterfallView(duration: dur)
                                .frame(height: 20)
                                .padding(.top, 4)
                        }
                    }


                    if request.requestBody != nil || request.responseBody != nil {
                        DetailSection(title: "Payload") {
                            PayloadView(request: request)
                        }
                    }

                    if let error = request.errorMessage {
                        DetailSection(title: "Error Log") {
                            Text(error)
                                .font(DS.Typography.metadata.monospaced())
                                .foregroundStyle(.red)
                                .padding(8)
                                .background(Color.red.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func formatFullTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct HeaderListView: View {
    let headers: [String: String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top) {
                    Text(key)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(value)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

struct WaterfallView: View {
    let duration: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: geo.size.width * CGFloat(min(duration, 5.0) / 5.0)) // Max 5s scale
            }
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(DS.Typography.metadata)
                .textSelection(.enabled)
                .lineLimit(5)
        }
    }
}
