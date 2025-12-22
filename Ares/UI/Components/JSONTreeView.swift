import SwiftUI

struct JSONTreeView: View {
    let jsonString: String
    @State private var parsedData: Any?
    @State private var parseError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let error = parseError {
                    Text("Invalid JSON: \(error)")
                        .foregroundColor(.red)
                        .font(.system(size: 11, design: .monospaced))
                } else if let data = parsedData {
                    JSONNodeView(key: "root", value: data, isRoot: true)
                } else {
                    Text("Parsing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
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
                            .font(.system(size: 8, weight: .bold))
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
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.purple)
                }
                
                // Value Display (Inline for primitives, braced for containers)
                if isContainer {
                    Text(containerStart)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if !isExpanded {
                        Text("...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(2)
                        
                        Text(containerEnd)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        // Item count for collapsed state
                        Text(itemCountDescription)
                            .font(.system(size: 10))
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
                            JSONNodeView(key: k, value: dict[k]!, isRoot: false)
                        }
                    } else if let array = value as? [Any] {
                        ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                             JSONNodeView(key: "\(index)", value: item, isRoot: false)
                        }
                    }
                }
                .padding(.leading, 20)
                
                // Closing brace
                HStack {
                    Spacer().frame(width: 12)
                    Text(containerEnd)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
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
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.green)
                .lineLimit(isRoot ? nil : 5) 
        } else if let num = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                Text(num.boolValue ? "true" : "false")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            } else {
                Text("\(num)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.blue)
            }
        } else if value is NSNull {
            Text("null")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
        } else {
            Text("\(String(describing: value))")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}
