import SwiftUI

/// View to display parsed URL-encoded form data
struct FormDataView: View {
    let formData: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.blue)
                Text("Form Data")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            // Parse and display form data
            let items = parseFormData(formData)
            ForEach(items, id: \.key) { item in
                FormDataRow(key: item.key, value: item.value)
            }
        }
    }

    /// Parse URL-encoded form data into key-value pairs
    private func parseFormData(_ data: String) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []

        let pairs = data.split(separator: "&", omittingEmptySubsequences: true)
        for pair in pairs {
            let keyValue = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if keyValue.count >= 1 {
                let key = String(keyValue[0]).removingPercentEncoding ?? String(keyValue[0])
                let value = keyValue.count > 1 ? (String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])) : ""
                result.append((key: key, value: value))
            }
        }

        return result
    }
}

/// Row for displaying a single form data key-value pair
struct FormDataRow: View {
    let key: String
    let value: String
    @State private var isExpanded = false

    private var isJSON: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                // Key
                Text(key)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.blue)
                    .frame(minWidth: 80, alignment: .leading)

                Text("=")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                // Value or expand button for JSON
                if isJSON {
                    Button(action: { isExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8))
                            Text(isExpanded ? "JSON Object" : "JSON Object (tap to expand)")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }

                Spacer()
            }

            // Expanded JSON view
            if isJSON && isExpanded {
                JSONTreeView(jsonString: value)
                    .padding(.leading, 16)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
    }
}
