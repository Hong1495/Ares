import SwiftUI

// MARK: - Data Models

struct TopologyNode: Identifiable {
    let id: String
    let label: String
    let type: NodeType
    var position: CGPoint = .zero
    var color: Color = .gray // Assigned source color

    enum NodeType {
        case source   // Process (e.g. Chrome)
        case rule     // Rule (e.g. DomainSuffix)
        case proxy    // Proxy Group (e.g. HK)
        case target   // Host (e.g. google.com)
    }
}

struct TopologyEdge: Identifiable {
    let id: UUID = UUID()
    let from: String
    let to: String
    var weight: Int
    var color: Color = .gray // Propagated color

    // Control Point Offsets for Bundling
    // Instead of moving start/end points, we move the control points perpendicular to the flow
    var controlOffset: CGFloat = 0

    // Animation Phase Offset (Randomized to avoid rhythmic jumping)
    var randomPhase: Double = Double.random(in: 0...1)
}

// MARK: - Topology Canvas View

struct TopologyView: View {
    let rows: [TopologyRow]
    @EnvironmentObject var appState: AppState
    @State private var nodeLookup: [String: TopologyNode] = [:]
    @State private var size: CGSize = .zero

    // Cache the graph to avoid recalculation on every frame
    @State private var graph: (nodes: [TopologyNode], edges: [TopologyEdge]) = ([], [])

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if graph.nodes.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyzing Network Topology...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    ZStack {
                        staticCanvas

                        if appState.animationsEnabled && appState.isForeground {
                            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                                particleCanvas(timeline: timeline)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onAppear {
                self.size = geometry.size
                updateGraph()
            }
            .onChange(of: geometry.size) { _, newSize in
                self.size = newSize
                updateGraph()
            }
            .onChange(of: rows) { _, _ in
                // Only update structure when data changes, NOT on every frame
                withAnimation(.easeInOut(duration: 0.5)) {
                    updateGraph()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var staticCanvas: some View {
        Canvas { context, size in
            drawStaticGraph(in: context, size: size)
        }
    }

    private func particleCanvas(timeline: TimelineViewDefaultContext) -> some View {
        Canvas { context, size in
            let time = timeline.date.timeIntervalSinceReferenceDate
            drawParticles(in: context, size: size, time: time)
        }
    }

    // Static layer: edges + nodes + labels (only re-rendered when graph changes)
    private func drawStaticGraph(in context: GraphicsContext, size: CGSize) {
        // Draw Edges (Curves)
        for edge in graph.edges {
            if let startNode = nodeLookup[edge.from],
               let endNode = nodeLookup[edge.to] {

                let start = startNode.position
                let end = endNode.position

                let midX = start.x + (end.x - start.x) * 0.5
                let control1 = CGPoint(x: midX, y: start.y + edge.controlOffset)
                let control2 = CGPoint(x: midX, y: end.y + edge.controlOffset)

                let path = Path { p in
                    p.move(to: start)
                    p.addCurve(to: end, control1: control1, control2: control2)
                }

                let gradient = Gradient(stops: [
                    .init(color: edge.color.opacity(0.8), location: 0),
                    .init(color: edge.color.opacity(0.4), location: 1.0)
                ])

                context.stroke(path, with: .linearGradient(gradient, startPoint: start, endPoint: end), lineWidth: min(3.5, 1.2 + log2(Double(edge.weight) + 1) * 0.35))
            }
        }

        // Draw Nodes
        for node in graph.nodes {
            let nodeRadius: CGFloat = 4
            let nodeRect = CGRect(x: node.position.x - nodeRadius, y: node.position.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)
            context.fill(Path(ellipseIn: nodeRect.insetBy(dx: -2, dy: -2)), with: .color(node.color.opacity(0.3)))
            context.fill(Path(ellipseIn: nodeRect), with: .color(node.color))

            let text = Text(node.label)
                .font(DS.Typography.caption.weight(.medium))
                .foregroundStyle(.primary)

            context.draw(text, at: CGPoint(x: node.position.x, y: node.position.y + 14), anchor: .top)
        }
    }

    // Animated layer: particles only (lightweight)
    private func drawParticles(in context: GraphicsContext, size: CGSize, time: Double) {
        let animatedEdges = graph.edges.prefix(30)
        let particleCount = 1

        for edge in animatedEdges {
            if let startNode = nodeLookup[edge.from],
               let endNode = nodeLookup[edge.to] {

                let start = startNode.position
                let end = endNode.position

                let midX = start.x + (end.x - start.x) * 0.5
                let control1 = CGPoint(x: midX, y: start.y + edge.controlOffset)
                let control2 = CGPoint(x: midX, y: end.y + edge.controlOffset)

                let path = Path { p in
                    p.move(to: start)
                    p.addCurve(to: end, control1: control1, control2: control2)
                }

                for i in 0..<particleCount {
                    let offset = (time * 0.4 + edge.randomPhase + Double(i) / Double(particleCount)).truncatingRemainder(dividingBy: 1.0)
                    if let point = path.trimmedPath(from: 0, to: CGFloat(offset)).currentPoint {
                        let particleSize = 3.0
                        let particleRect = CGRect(x: point.x - particleSize / 2, y: point.y - particleSize / 2, width: particleSize, height: particleSize)
                        context.fill(Path(ellipseIn: particleRect), with: .color(edge.color))
                    }
                }
            }
        }
    }

    // MARK: - Graph Algorithm

    func updateGraph() {
        let newGraph = calculateGraph(rows: rows, size: size)
        self.graph = newGraph
        nodeLookup = Dictionary(uniqueKeysWithValues: newGraph.nodes.map { ($0.id, $0) })
    }

    func calculateGraph(rows: [TopologyRow], size: CGSize) -> (nodes: [TopologyNode], edges: [TopologyEdge]) {
        var nodes: [String: TopologyNode] = [:]

        let width = size.width
        let height = size.height
        let centerY = height / 2

        if width == 0 || height == 0 { return ([], []) }

        let col1X = width * 0.1
        let col2X = width * 0.35
        let col3X = width * 0.65
        let col4X = width * 0.9

        var sources = Set<String>()
        var rules = Set<String>()
        var proxies = Set<String>()
        var targets = Set<String>()
        var sourceColors: [String: Color] = [:]

        let topChains = rows // Every active connection contributes; only duplicate edges are merged.

        for chain in topChains {
            let source = chain.source
            let rule = chain.rule
            let target = chain.target
            let proxy = chain.proxy

            sources.insert(source)
            rules.insert(rule)
            proxies.insert(proxy)
            targets.insert(target)

            if sourceColors[source] == nil {
                sourceColors[source] = generateColor(for: source)
            }
        }

        func layoutColumn(items: [String], x: CGFloat, type: TopologyNode.NodeType) {
            let count = items.count
            let step = count > 1 ? height / CGFloat(count + 1) : height / 2
            let sortedItems = items.sorted()

            for (index, item) in sortedItems.enumerated() {
                let y = count > 1 ? step * CGFloat(index + 1) : centerY
                let id = "\(type)_\(item)"

                var nodeColor: Color = .gray
                if type == .source {
                    nodeColor = sourceColors[item] ?? .blue
                } else if type == .target {
                    nodeColor = .green
                } else if type == .proxy {
                    nodeColor = .orange
                } else {
                    nodeColor = .purple
                }

                let node = TopologyNode(id: id, label: item, type: type, position: CGPoint(x: x, y: y), color: nodeColor)
                nodes[id] = node
            }
        }

        layoutColumn(items: Array(sources), x: col1X, type: .source)
        layoutColumn(items: Array(rules), x: col2X, type: .rule)
        layoutColumn(items: Array(proxies), x: col3X, type: .proxy)
        layoutColumn(items: Array(targets), x: col4X, type: .target)

        struct EdgeKey: Hashable {
            let from: String
            let to: String
            let source: String
        }
        var edgesByKey: [EdgeKey: TopologyEdge] = [:]

        func addEdge(uName: String, uType: TopologyNode.NodeType, vName: String, vType: TopologyNode.NodeType, sourceName: String) {
            let uID = "\(uType)_\(uName)"
            let vID = "\(vType)_\(vName)"

            if nodes[uID] != nil && nodes[vID] != nil {
                let color = sourceColors[sourceName] ?? .gray
                let key = EdgeKey(from: uID, to: vID, source: sourceName)
                if var edge = edgesByKey[key] {
                    edge.weight += 1
                    edgesByKey[key] = edge
                } else {
                    edgesByKey[key] = TopologyEdge(from: uID, to: vID, weight: 1, color: color)
                }
            }
        }

        for chain in topChains {
            let source = chain.source
            let rule = chain.rule
            let proxy = chain.proxy
            let target = chain.target

            addEdge(uName: source, uType: .source, vName: rule, vType: .rule, sourceName: source)
            addEdge(uName: rule, uType: .rule, vName: proxy, vType: .proxy, sourceName: source)
            addEdge(uName: proxy, uType: .proxy, vName: target, vType: .target, sourceName: source)
        }

        // Sort for stable lane placement, then assign offsets in linear time.
        let rawEdges = edgesByKey.sorted {
            ($0.key.from, $0.key.to, $0.key.source) < ($1.key.from, $1.key.to, $1.key.source)
        }.map(\.value)
        struct Pair: Hashable { let from: String; let to: String }
        var counts: [Pair: Int] = [:]
        for edge in rawEdges { counts[Pair(from: edge.from, to: edge.to), default: 0] += 1 }
        var offsets: [Pair: Int] = [:]
        let finalEdges = rawEdges.map { edge in
            var result = edge
            let pair = Pair(from: edge.from, to: edge.to)
            let index = offsets[pair, default: 0]
            offsets[pair] = index + 1
            result.controlOffset = calculateControlOffset(index: index, total: counts[pair, default: 1])
            return result
        }

        return (Array(nodes.values), finalEdges)
    }

    func calculateControlOffset(index: Int, total: Int) -> CGFloat {
        if total <= 1 { return 0 }
        let maxSpread: CGFloat = 40.0
        let step = maxSpread / CGFloat(total)
        let start = -maxSpread / 2.0 + step / 2.0
        return start + CGFloat(index) * step
    }

    func generateColor(for string: String) -> Color {
        let hash = string.hashValue.magnitude
        let colors: [Color] = [
            .blue, .red, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .teal
        ]
        return colors[Int(hash % UInt(colors.count))]
    }
}
