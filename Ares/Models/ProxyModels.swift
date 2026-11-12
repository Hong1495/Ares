import Foundation

/// Proxy node model
nonisolated struct ProxyNode: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let type: String
    var delay: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, type, delay
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(String.self, forKey: .type)
        self.delay = try? container.decode(Int.self, forKey: .delay)
        self.id = name
    }
    
    init(id: String = UUID().uuidString, name: String, type: String, delay: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.delay = delay
    }
}

/// Represents an item in a proxy group's selection list
nonisolated enum ProxyItem: Hashable, Identifiable, Sendable {
    case group(String)      // Another proxy group
    case node(String)       // An actual proxy node
    case special(String)    // DIRECT, REJECT, etc.
    
    var id: String {
        switch self {
        case .group(let name), .node(let name), .special(let name):
            return name
        }
    }
    
    var name: String {
        switch self {
        case .group(let name), .node(let name), .special(let name):
            return name
        }
    }
    
    var isSelectable: Bool {
        true // A group is also a valid member of a selector.
    }
}

/// Proxy Group (Selector, URLTest, etc.)
nonisolated struct ProxyGroup: Identifiable, Codable, Sendable {
    var id: String { name }
    let name: String
    let type: String
    var now: String?
    var fixed: String?
    let all: [String]

    var supportsManualSelection: Bool {
        ["Selector", "URLTest", "Fallback"].contains(type)
    }
    var supportsAutomaticSelection: Bool { type == "URLTest" || type == "Fallback" }
    var manualSelection: String? {
        if type == "Selector" { return now }
        return fixed.flatMap { $0.isEmpty ? nil : $0 }
    }

    func confirmsSelection(_ node: String) -> Bool {
        supportsManualSelection && all.contains(node) && manualSelection == node
    }
    
    // Computed: classify items in all array
    func classifyItems(groups: [ProxyGroup], nodes: [String: ProxyNode]) -> [ProxyItem] {
        all.map { itemName in
            if groups.contains(where: { $0.name == itemName }) {
                return .group(itemName)
            } else if nodes[itemName] != nil {
                return .node(itemName)
            } else {
                return .special(itemName)  // DIRECT, REJECT, etc.
            }
        }
    }
    
    // Resolve the full path to the currently selected node
    func resolveCurrentPath(groups: [ProxyGroup]) -> [String] {
        var path = [name]
        var current = now
        var visited: Set<String> = [name]
        
        while let currentName = current,
              let nextGroup = groups.first(where: { $0.name == currentName }) {
            guard visited.insert(currentName).inserted else { return path }
            path.append(nextGroup.name)
            current = nextGroup.now
        }
        
        // Add final node if exists
        if let finalNode = current {
            path.append(finalNode)
        }
        
        return path
    }
    
    enum CodingKeys: String, CodingKey {
        case name, type, now, fixed, all
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(String.self, forKey: .type)
        self.now = try? container.decode(String.self, forKey: .now)
        self.fixed = try? container.decode(String.self, forKey: .fixed)
        self.all = (try? container.decode([String].self, forKey: .all)) ?? []
    }
    
    init(name: String, type: String, now: String? = nil, fixed: String? = nil, all: [String] = []) {
        self.name = name
        self.type = type
        self.now = now
        self.fixed = fixed
        self.all = all
    }
}
