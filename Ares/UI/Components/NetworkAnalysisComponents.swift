import SwiftUI

// MARK: - Shared Views

struct TabRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "safari")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? "Untitled Tab" : tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                    .lineLimit(1)
                
                Text(tab.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer(minLength: 4)
            
            if !tab.requests.isEmpty {
                Text("\(tab.requests.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                    .foregroundStyle(isSelected ? .white : .blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

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
                        .font(.system(size: 10, weight: .bold))
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
                                .font(.system(size: 11, design: .monospaced))
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(value)
                        .font(.system(size: 10))
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
                .font(.system(size: 10, weight: .bold))
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
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineLimit(5)
        }
    }
}

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
                .font(.system(size: 11, weight: .bold))
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
                .font(.system(size: 10))
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
                    .font(.system(size: 10, design: .monospaced))
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

// MARK: - Hex Dump View for Binary Data

/// View to display binary data as hex dump with ASCII sidebar
struct HexDumpView: View {
    let data: Data
    let bytesPerRow: Int = 16
    let maxRows: Int = 64 // Limit to ~1KB display
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "01.square")
                    .foregroundStyle(.purple)
                Text("Binary Data")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(data.count) bytes")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("Offset")
                            .frame(width: 60, alignment: .leading)
                        Text("00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F")
                            .frame(width: 380, alignment: .leading)
                        Text("ASCII")
                            .frame(width: 140, alignment: .leading)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)
                    
                    // Data rows
                    let totalRows = min((data.count + bytesPerRow - 1) / bytesPerRow, maxRows)
                    ForEach(0..<totalRows, id: \.self) { rowIndex in
                        HexRow(data: data, rowIndex: rowIndex, bytesPerRow: bytesPerRow)
                    }
                    
                    if data.count > maxRows * bytesPerRow {
                        Text("... \(data.count - maxRows * bytesPerRow) more bytes truncated")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

/// Single row in hex dump view
struct HexRow: View {
    let data: Data
    let rowIndex: Int
    let bytesPerRow: Int
    
    var body: some View {
        let startOffset = rowIndex * bytesPerRow
        let endOffset = min(startOffset + bytesPerRow, data.count)
        let rowData = data[startOffset..<endOffset]
        
        HStack(spacing: 0) {
            // Offset
            Text(String(format: "%06X", startOffset))
                .frame(width: 60, alignment: .leading)
                .foregroundStyle(.blue)
            
            // Hex bytes
            HStack(spacing: 0) {
                ForEach(0..<bytesPerRow, id: \.self) { i in
                    let byteIndex = startOffset + i
                    if byteIndex < data.count {
                        Text(String(format: "%02X ", data[byteIndex]))
                            .foregroundStyle(isPrintable(data[byteIndex]) ? .primary : .secondary)
                    } else {
                        Text("   ")
                    }
                    if i == 7 {
                        Text(" ")
                    }
                }
            }
            .frame(width: 380, alignment: .leading)
            
            // ASCII
            Text(asciiRepresentation(rowData))
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.green.opacity(0.8))
        }
        .font(.system(size: 9, design: .monospaced))
    }
    
    private func isPrintable(_ byte: UInt8) -> Bool {
        byte >= 32 && byte < 127
    }
    
    private func asciiRepresentation(_ data: Data.SubSequence) -> String {
        String(data.map { isPrintable($0) ? Character(UnicodeScalar($0)) : "." })
    }
}

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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let boundary = boundary {
                    Text("boundary: \(boundary.prefix(20))...")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Divider()
            
            let parts = parseMultipart(content, boundary: boundary)
            if parts.isEmpty {
                Text("Unable to parse multipart data")
                    .font(.system(size: 10))
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                
                Text(part.name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.blue)
                
                if let filename = part.filename {
                    Text("(\(filename))")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                
                if let ct = part.contentType {
                    Text("[\(ct)]")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                Text(part.value.prefix(500) + (part.value.count > 500 ? "..." : ""))
                    .font(.system(size: 9, design: .monospaced))
                    .padding(6)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
    }
}




struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct StatusIndicator: View {
    @ObservedObject private var service = BrowserAnalysisService.shared
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: service.activeTabs.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(service.activeTabs.isEmpty ? Color.secondary : Color.green)
            
            Circle()
                .fill(service.activeTabs.isEmpty ? Color.secondary : Color.green)
                .frame(width: 6, height: 6)
            
            Text(service.activeTabs.isEmpty ? "No active sessions" : "Monitoring Network Traffic")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("Search...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No Activity Captured")
                .font(.system(size: 13, weight: .medium))
            Text("Network requests for this tab will appear here in real-time.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .opacity(0.6)
    }
}

func formatShortNetworkTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}
