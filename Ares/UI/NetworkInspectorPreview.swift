import SwiftUI

struct RichContentPreview: View {
    let request: BrowserRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let body = request.responseBody, !body.isEmpty {
                // Clean body (remove possible chunked encoding residue)
                let cleanBody = cleanChunkedResidue(body)

                // 1. Determine Content Type
                let contentType = request.responseHeaders?.first(where: { $0.key.lowercased() == "content-type" })?.value.lowercased() ?? ""

                // 2. Dispatch to correct view
                if contentType.contains("image") {
                    renderImage(cleanBody, contentType: contentType)
                } else if contentType.contains("css") || contentType.contains("javascript") || contentType.contains("html") || contentType.contains("xml") {
                    CodeView(code: cleanBody, lang: languageFor(contentType))
                } else if cleanBody.looksLikeJSON {
                    JSONTreeView(jsonString: cleanBody.preprocessJSON)
                } else {
                    // Default Text View
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Size: \(formatSize(cleanBody.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(cleanBody)
                                .font(DS.Typography.body.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                }
            } else {
                EmptyState(text: "No Content Available")
            }
        }
    }



    /// Clean chunked encoding residue from body
    /// Handles cases like "28\n[[9,["noop"]]...]" -> "[[9,["noop"]]...]"
    private func cleanChunkedResidue(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for pattern: hex number followed by newline then actual content
        // Common chunked residue: "xx\n{...}" or "xx\r\n{...}"
        if let firstNewline = trimmed.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let potentialChunkSize = String(trimmed[..<firstNewline])
            // Check if it's a valid hex number (chunked size)
            if potentialChunkSize.count <= 8, // Reasonable chunk size hex
               potentialChunkSize.allSatisfy({ $0.isHexDigit }) {
                // Skip past the chunk size and newlines
                var afterNewline = trimmed.index(after: firstNewline)
                while afterNewline < trimmed.endIndex && (trimmed[afterNewline] == "\n" || trimmed[afterNewline] == "\r") {
                    afterNewline = trimmed.index(after: afterNewline)
                }
                let remainder = String(trimmed[afterNewline...])
                // Also strip trailing "0\r\n\r\n" or similar end markers
                return remainder.replacingOccurrences(of: "\r\n0\r\n\r\n", with: "")
                    .replacingOccurrences(of: "\n0\n\n", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmed
    }


    @ViewBuilder
    func renderImage(_ body: String, contentType: String) -> some View {

        if contentType.contains("svg") {
            // SVG Handling
            // 1. Try treating as Base64 first (common from CDP)
            if let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) {
                // If it renders as image
                if let nsImage = NSImage(data: data) {
                    ImagePreview(image: nsImage, info: "SVG Image (Decoded)")
                }
                // If not image, maybe it's text/xml?
                else if let decodedString = String(data: data, encoding: .utf8) {
                    CodeView(code: decodedString, lang: "svg")
                } else {
                     // Failed to decode to string, show raw
                    CodeView(code: body, lang: "svg")
                }
            }
            // 2. Try treating as Raw XML String
            else if let data = body.data(using: .utf8), let nsImage = NSImage(data: data) {
                 ImagePreview(image: nsImage, info: "SVG Image")
            } else {
                // Fallback: Just show the text (it might be malformed XML)
                CodeView(code: body, lang: "svg")
            }
        } else {
            // Binary Image (Base64)
            if let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters), let nsImage = NSImage(data: data) {
                ImagePreview(image: nsImage, info: "\(contentType) (Base64)")
            } else {
                // Last ditch: maybe it was NOT base64 but raw binary passed as string? (Unlikely in Swift/JSON)
                VStack {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Image decode failed")
                        .foregroundColor(.secondary)
                        .padding()
                    Text("Size: \(formatSize(body.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func languageFor(_ type: String) -> String {
        if type.contains("css") { return "css" }
        if type.contains("javascript") { return "js" }
        if type.contains("html") { return "html" }
        if type.contains("xml") { return "xml" }
        return "text"
    }

    func formatSize(_ size: Int) -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct ImagePreview: View {
    let image: NSImage
    let info: String

    var body: some View {
        VStack {
            Spacer()
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .shadow(radius: 2)

            Text("\(Int(image.size.width)) x \(Int(image.size.height)) - \(info)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.canvas)
    }
}
