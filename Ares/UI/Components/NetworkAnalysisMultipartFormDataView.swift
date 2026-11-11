import SwiftUI

// MARK: - Multipart Form Data View

/// View to display parsed multipart/form-data content
struct MultipartFormDataView: View {
    let content: String
    let boundary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.green)
                Text("Multipart Form Data")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let boundary = boundary {
                    Text("boundary: \(boundary.prefix(20))...")
                        .font(DS.Typography.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            let parts = parseMultipart(content, boundary: boundary)
            if parts.isEmpty {
                Text("Unable to parse multipart data")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(parts.indices, id: \.self) { index in
                    MultipartPartView(part: parts[index], index: index)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    private func parseMultipart(_ content: String, boundary: String?) -> [(name: String, filename: String?, contentType: String?, value: String)] {
        guard let boundary = boundary else { return [] }
        var result: [(name: String, filename: String?, contentType: String?, value: String)] = []

        let parts = content.components(separatedBy: "--\(boundary)")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "--" { continue }

            // Split headers and body
            if let headerEnd = trimmed.range(of: "\r\n\r\n") ?? trimmed.range(of: "\n\n") {
                let headers = String(trimmed[..<headerEnd.lowerBound])
                let body = String(trimmed[headerEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Parse Content-Disposition
                var name = "unknown"
                var filename: String? = nil
                var contentType: String? = nil

                for line in headers.components(separatedBy: .newlines) {
                    let lower = line.lowercased()
                    if lower.contains("content-disposition") {
                        if let nameMatch = line.range(of: "name=\"", options: .caseInsensitive) {
                            let start = nameMatch.upperBound
                            if let end = line[start...].firstIndex(of: "\"") {
                                name = String(line[start..<end])
                            }
                        }
                        if let fnMatch = line.range(of: "filename=\"", options: .caseInsensitive) {
                            let start = fnMatch.upperBound
                            if let end = line[start...].firstIndex(of: "\"") {
                                filename = String(line[start..<end])
                            }
                        }
                    } else if lower.contains("content-type") {
                        contentType = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                    }
                }

                result.append((name: name, filename: filename, contentType: contentType, value: body))
            }
        }

        return result
    }
}

/// View for a single multipart part
struct MultipartPartView: View {
    let part: (name: String, filename: String?, contentType: String?, value: String)
    let index: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(index + 1).")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Text(part.name)
                    .font(DS.Typography.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.blue)

                if let filename = part.filename {
                    Text("(\(filename))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.orange)
                }

                if let ct = part.contentType {
                    Text("[\(ct)]")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Text(part.value.prefix(500) + (part.value.count > 500 ? "..." : ""))
                    .font(DS.Typography.caption.monospaced())
                    .padding(6)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
    }
}
