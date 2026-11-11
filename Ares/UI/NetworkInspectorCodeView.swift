import SwiftUI

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
                        .font(DS.Typography.secondary)
                }
                .padding(6)
                .background(DS.surface)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

                Spacer()

                Text(lang.uppercased())
                    .font(DS.Typography.caption.weight(.semibold))
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
                        .font(DS.Typography.metadata)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            .background(DS.canvas)

            Divider()

            ScrollView {
                Text(highlightedCode)
                    .font(DS.Typography.body.monospaced())
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
