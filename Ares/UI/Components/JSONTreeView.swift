import SwiftUI

struct JSONTreeView: View {
    let jsonString: String
    @State private var parsedData: Any?
    @State private var parseError: String?
    @State private var searchText: String = ""
    @State private var isCopied: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter via JSON path...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DS.Typography.secondary)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonString, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
                } label: {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(DS.Typography.metadata)
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading) {
                    if let error = parseError {
                        Text("Invalid JSON: \(error)")
                            .foregroundColor(.red)
                            .font(DS.Typography.metadata.monospaced())
                    } else if let data = parsedData {
                        JSONNodeView(key: "root", value: data, isRoot: true, searchText: searchText)
                    } else {
                        Text("Parsing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            parseJSON()
        }
        .onChange(of: jsonString) { _, _ in
            parseJSON()
        }
    }
    
    private func parseJSON() {
        guard let data = jsonString.data(using: .utf8) else {
            parseError = "Encoding Error"
            return
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            parsedData = object
            parseError = nil
        } catch {
            parseError = error.localizedDescription
        }
    }
}

struct JSONNodeView: View {
    let key: String?
    let value: Any
    let isRoot: Bool
    var searchText: String
    
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                // Expand/Collapse Button for containers
                if isContainer {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                } else {
                    Spacer().frame(width: 12)
                }
                
                // Key Display
                if let key = key, !isRoot {
                    Text("\(key):")
                        .font(DS.Typography.body.monospaced().weight(.semibold))
                        .foregroundColor(.purple)
                        .background(highlightColor(for: key))
                }
                
                // Value Display (Inline for primitives, braced for containers)
                if isContainer {
                    Text(containerStart)
                        .font(DS.Typography.body.monospaced())
                        .foregroundColor(.secondary)
                    
                    if !isExpanded {
                        Text("...")
                            .font(DS.Typography.body.monospaced())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(2)
                        
                        Text(containerEnd)
                            .font(DS.Typography.body.monospaced())
                            .foregroundColor(.secondary)
                        
                        // Item count for collapsed state
                        Text(itemCountDescription)
                            .font(DS.Typography.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                } else {
                    primitiveValueView
                }
            }
            
            // Expanded Content for containers
            if isContainer && isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    if let dict = value as? [String: Any] {
                        ForEach(dict.keys.sorted(), id: \.self) { k in
                            JSONNodeView(key: k, value: dict[k]!, isRoot: false, searchText: searchText)
                        }
                    } else if let array = value as? [Any] {
                        ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                             JSONNodeView(key: "\(index)", value: item, isRoot: false, searchText: searchText)
                        }
                    }
                }
                .padding(.leading, 20)
                
                // Closing brace
                HStack {
                    Spacer().frame(width: 12)
                    Text(containerEnd)
                        .font(DS.Typography.body.monospaced())
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    func highlightColor(for text: String) -> Color {
        if !searchText.isEmpty && text.localizedCaseInsensitiveContains(searchText) {
            return Color.yellow.opacity(0.3)
        }
        return Color.clear
    }
    
    var isContainer: Bool {
        return value is [String: Any] || value is [Any]
    }
    
    var containerStart: String {
        if value is [String: Any] { return "{" }
        if value is [Any] { return "[" }
        return ""
    }
    
    var containerEnd: String {
        if value is [String: Any] { return "}" }
        if value is [Any] { return "]" }
        return ""
    }
    
    var itemCountDescription: String {
        if let d = value as? [String: Any] { return "\(d.count) items" }
        if let a = value as? [Any] { return "\(a.count) items" }
        return ""
    }
    
    @ViewBuilder
    var primitiveValueView: some View {
        if let str = value as? String {
            Text("\"\(str)\"")
                .font(DS.Typography.body.monospaced())
                .foregroundColor(.green)
                .lineLimit(isRoot ? nil : 5) 
                .background(highlightColor(for: str)) 
        } else if let num = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                Text(num.boolValue ? "true" : "false")
                    .font(DS.Typography.body.monospaced().weight(.semibold))
                    .foregroundColor(.orange)
            } else {
                Text("\(num)")
                    .font(DS.Typography.body.monospaced())
                    .foregroundColor(.blue)
            }
        } else if value is NSNull {
            Text("null")
                .font(DS.Typography.body.monospaced().weight(.semibold))
                .foregroundColor(.red)
        } else {
            Text("\(String(describing: value))")
                .font(DS.Typography.body.monospaced())
                .foregroundColor(.primary)
                .background(highlightColor(for: String(describing: value)))
        }
    }
}
