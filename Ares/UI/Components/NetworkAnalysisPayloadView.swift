import SwiftUI

struct PayloadView: View {
    let request: BrowserRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let reqBody = request.requestBody, !reqBody.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Request Body", content: reqBody)
                        BodyTextView(text: reqBody)
                    }
                }

                if let resBody = request.responseBody, !resBody.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Response Body", content: resBody)
                        BodyTextView(text: resBody)
                    }
                }
            }
            .padding()
        }
    }
}

struct SectionHeader: View {
    let title: String
    let content: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
                withAnimation {
                    copied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy")
                }
                .font(DS.Typography.caption)
                .foregroundStyle(copied ? .green : .blue)
            }
            .buttonStyle(.plain)
        }
    }
}

struct BodyTextView: View {
    let text: String
    var contentType: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Check if it looks like JSON
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ||
               text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                JSONTreeView(jsonString: text)
                    .padding(8)
            }
            // Check if it's multipart/form-data
            else if isMultipartFormData(text, contentType: contentType) {
                MultipartFormDataView(content: text, boundary: extractBoundary(contentType))
                    .padding(8)
            }
            // Check if it looks like URL-encoded form data
            else if isURLEncodedFormData(text) {
                FormDataView(formData: text)
                    .padding(8)
            } else {
                Text(text)
                    .font(DS.Typography.caption.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    /// Check if text appears to be URL-encoded form data
    private func isURLEncodedFormData(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must contain = and likely contains & or common encoded chars
        guard trimmed.contains("=") else { return false }
        // Check for URL encoding patterns
        let hasAmpersand = trimmed.contains("&")
        let hasPercentEncoding = trimmed.contains("%")
        let hasJsonPrefix = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        return (hasAmpersand || hasPercentEncoding) && !hasJsonPrefix
    }

    /// Check if content is multipart/form-data
    private func isMultipartFormData(_ text: String, contentType: String?) -> Bool {
        // Check content type header
        if let ct = contentType?.lowercased(), ct.contains("multipart/form-data") {
            return true
        }
        // Check for boundary pattern in content
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("--") && trimmed.contains("Content-Disposition")
    }

    /// Extract boundary from content-type header
    private func extractBoundary(_ contentType: String?) -> String? {
        guard let ct = contentType else { return nil }
        if let range = ct.range(of: "boundary=", options: .caseInsensitive) {
            var boundary = String(ct[range.upperBound...])
            // Remove quotes if present
            boundary = boundary.trimmingCharacters(in: .init(charactersIn: "\""))
            // Take until semicolon or end
            if let semi = boundary.firstIndex(of: ";") {
                boundary = String(boundary[..<semi])
            }
            return boundary.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
