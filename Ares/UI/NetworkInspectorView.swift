import SwiftUI

struct NetworkInspectorView: View {
    let requestId: String
    @ObservedObject var service = BrowserAnalysisService.shared

    // Tab State
    enum InspectorTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case headers = "Headers"
        case payload = "Payload"
        case preview = "Preview"
        case response = "Response"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "chart.bar.doc.horizontal"
            case .headers: return "list.bullet.rectangle"
            case .payload: return "doc.text.magnifyingglass"
            case .preview: return "eye"
            case .response: return "arrow.down.circle"
            }
        }
    }

    @State private var selectedTab: InspectorTab = .overview

    var request: BrowserRequest? {
        // Search all tabs to find the request by ID
        for tab in service.activeTabs {
            if let req = tab.requests.first(where: { $0.id == requestId }) {
                return req
            }
            // Also check history even if merged
            for req in tab.requests {
                if req.hits.contains(where: { $0.id.uuidString == requestId }) {
                    return req
                }
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if let req = request {
                NavigationSplitView {
                    List(InspectorTab.allCases, selection: $selectedTab) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.rawValue, systemImage: tab.icon)
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("Inspector")
                } detail: {
                    VStack(spacing: 0) {
                        // Header
                        InspectorHeader(request: req)
                        Divider()

                        // Main Inspector Content
                        ZStack {
                            Color(nsColor: .textBackgroundColor) // Clean background

                            switch selectedTab {
                            case .overview:
                                AnalysisInspector(request: req)
                            case .headers:
                                HeadersInspector(request: req)
                            case .payload:
                                PayloadInspector(request: req)
                            case .preview:
                                PreviewInspector(request: req)
                            case .response:
                                ResponseInspector(request: req)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Request Not Found")
                        .font(.headline)
                    Text("ID: \(requestId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .navigationTitle("Inspect Network Details")
        .onAppear {
             if let window = NSApp.windows.first(where: { $0.title == "Inspect Network Details" }) {
                window.zoom(nil)
            }
        }
    }
}

// MARK: - Components

struct InspectorHeader: View {
    let request: BrowserRequest

    var body: some View {
        HStack(spacing: 12) {
            // Method Badge
            Text(request.method)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(methodColor(request.method).opacity(0.1))
                .foregroundColor(methodColor(request.method))
                .cornerRadius(4)

            // URL
            Text(request.url)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Status Code
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(request))
                    .frame(width: 8, height: 8)
                if let code = request.statusCode {
                    Text("\(code)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(statusColor(request))
                } else {
                    Text(request.status.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(statusColor(request))
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return .green
        case "POST": return .blue
        case "DELETE": return .red
        case "PUT": return .orange
        default: return .secondary
        }
    }

    private func statusColor(_ req: BrowserRequest) -> Color {
        if req.status == .error || (req.statusCode ?? 200) >= 400 { return .red }
        if req.status == .pending { return .orange }
        return .green
    }
}



// MARK: - Inspectors

struct HeadersInspector: View {
    let request: BrowserRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General
                SectionView(title: "General") {
                    KeyValueRow(key: "Request URL", value: request.url)
                    KeyValueRow(key: "Request Method", value: request.method)
                    KeyValueRow(key: "Status Code", value: "\(request.statusCode ?? 0) \(request.status.rawValue)")
                    KeyValueRow(key: "Remote Address", value: request.remoteAddress ?? "-")
                }

                // Response Headers
                if let headers = request.responseHeaders {
                    SectionView(title: "Response Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            KeyValueRow(key: key, value: value)
                        }
                    }
                }

                // Request Headers
                if let headers = request.requestHeaders {
                    SectionView(title: "Request Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            KeyValueRow(key: key, value: value)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct PayloadInspector: View {
    let request: BrowserRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Query String Parameters always on top if present
            if let urlComponents = URLComponents(string: request.url), let items = urlComponents.queryItems, !items.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        SectionView(title: "Query String Parameters") {
                            ForEach(items, id: \.name) { item in
                                KeyValueRow(key: item.name, value: item.value ?? "")
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 150) // Limit height for query params
                Divider()
            }

            if let body = request.requestBody, !body.isEmpty {
                // Use unified JSON detection logic
                if body.looksLikeJSON {
                     // Full screen JSON with preprocessing
                     JSONTreeView(jsonString: body.preprocessJSON)
                 } else {
                     ScrollView {
                         BodyTextView(text: body)
                            .padding()
                     }
                 }
            } else {
                EmptyState(text: "No Request Payload")
            }
        }
    }
}

struct PreviewInspector: View {
    let request: BrowserRequest

    var body: some View {
         RichContentPreview(request: request)
    }
}

struct ResponseInspector: View {
    let request: BrowserRequest

    var body: some View {
        RichContentPreview(request: request)
    }
}

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
                                .font(.system(size: 13, design: .monospaced))
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CodeView: View {
    let code: String
    let lang: String
    @State private var formattedCode: String?
    @State private var searchText = ""
    @State private var isCopied = false

    var displayCode: String {
        formattedCode ?? code
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search code...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

                Spacer()

                Text(lang.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayCode, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
                } label: {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                Text(highlightedCode)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .task {
             formattedCode = BasicFormatter.format(code)
        }
    }

    var highlightedCode: AttributedString {
        let text = displayCode
        var attributed = AttributedString(text)
        attributed.foregroundColor = colorForLang(lang)

        if !searchText.isEmpty {
            // Find all ranges (Case insensitive)
            var range = attributed.startIndex..<attributed.endIndex
            while let match = attributed[range].range(of: searchText, options: .caseInsensitive) {
                attributed[match].backgroundColor = .yellow.opacity(0.3)
                attributed[match].foregroundColor = .black
                // Move search range forward
                if match.upperBound == attributed.endIndex { break }
                range = match.upperBound..<attributed.endIndex
            }
        }

        return attributed
    }

    func colorForLang(_ lang: String) -> Color {
        switch lang {
        case "css": return .blue
        case "js": return .orange
        case "html", "xml", "svg": return .purple
        default: return .primary
        }
    }
}

struct BasicFormatter {
    static func format(_ code: String) -> String {
        // Very basic brace-based formatter for JS/CSS
        var formatted = ""
        var indent = 0
        let indentStr = "  "

        // Normalize newlines (Use with caution on code with comments)
        let clean = code.replacingOccurrences(of: "\n", with: "")
                        .replacingOccurrences(of: "\r", with: "")

        let charArray = Array(clean)
        for i in 0..<charArray.count {
            let char = charArray[i]

            if char == "{" {
                formatted.append(" {\n")
                indent += 1
                formatted.append(String(repeating: indentStr, count: indent))
            } else if char == "}" {
                formatted.append("\n")
                indent = max(0, indent - 1)
                formatted.append(String(repeating: indentStr, count: indent))
                formatted.append("}")
            } else if char == ";" {
                formatted.append(";\n")
                formatted.append(String(repeating: indentStr, count: indent))
            } else {
                formatted.append(char)
            }
        }
        return formatted
    }
}



// MARK: - Helpers

struct SectionView<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            content
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key + ":")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundColor(.secondary)
            Text("Verify extension settings if content is missing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
