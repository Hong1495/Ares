import SwiftUI
import WebKit

struct Edge: Decodable, Identifiable {
    let id: String
    let name: String
    let from: [Double]
    let to: [Double]
    let points: [[Double]]
    let count: Int
    let bytes: Int64
}
struct Fixture: Decodable {
    let name: String
    let total: Int
    let unlocated: Int
    let bytes: Int64
    let edges: [Edge]
}
struct LabData {
    let fixtures: [Fixture]
    let polygons: [[[Double]]]
    let assets: URL
    init() throws {
        assets = Bundle.main.resourceURL!.appendingPathComponent("assets")
        fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: assets.appendingPathComponent("fixtures.json")))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: assets.appendingPathComponent("world.geojson"))) as! [String: Any]
        var rings: [[[Double]]] = []
        for item in root["features"] as! [[String: Any]] {
            let geometry = item["geometry"] as! [String: Any]
            if geometry["type"] as? String == "Polygon" { rings += geometry["coordinates"] as! [[[Double]]] }
            else if geometry["type"] as? String == "MultiPolygon" { rings += (geometry["coordinates"] as! [[[[Double]]]]).flatMap { $0 } }
        }
        polygons = rings
    }
}
@main struct RoutingLab: App {
    let data: LabData
    init() { do { data = try LabData() } catch { fatalError("Fixture load failed: \(error)") } }
    var body: some Scene {
        WindowGroup("Ares · Routing Lab") { LabView(data: data).frame(minWidth: 900, minHeight: 620) }
            .defaultSize(width: 1180, height: 760)
    }
}
struct LabView: View {
    let data: LabData
    @State private var renderer = 0
    @State private var scenario = 0
    @State private var dark = false
    @State private var selected: String? = nil
    @State private var command = "world"
    @State private var commandRevision = 0
    @State private var metrics = "Loading local assets…"
    @State private var filter = ""
    var fixture: Fixture { data.fixtures[scenario] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Routing").font(.system(size: 15, weight: .semibold))
                    Text("Technology preview · Simulated data").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Renderer", selection: $renderer) { Text("MapLibre").tag(0); Text("Native Canvas").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
                Toggle("Dark", isOn: $dark).toggleStyle(.switch).controlSize(.small)
            }.padding(16)
            HStack(spacing: 18) {
                Picker("Scenario", selection: $scenario) { ForEach(data.fixtures.indices, id: \.self) { Text(data.fixtures[$0].name).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 270)
                stat("\(fixture.total)", "connections")
                stat("\(fixture.edges.count)", "routes")
                stat("\(fixture.unlocated)", "unlocated")
                Spacer()
                Button("World") { send("world") }
                Button("Fit All") { send("all") }
                Button("Fit Selection") { send("selection") }.disabled(selected == nil)
                Button { send("out") } label: { Image(systemName: "minus") }.help("Zoom out")
                Button { send("in") } label: { Image(systemName: "plus") }.help("Zoom in")
            }.controlSize(.small).padding(.horizontal,16).padding(.bottom,12)
            HSplitView {
                ZStack(alignment: .bottomLeading) {
                    if renderer == 0 {
                        MapWebView(assets: data.assets, scenario: scenario, dark: dark, selected: $selected,
                                   command: command, revision: commandRevision, metrics: $metrics)
                    } else {
                        NativeMap(polygons: data.polygons, edges: fixture.edges, dark: dark, selected: $selected,
                                  command: command, revision: commandRevision, scenario: scenario)
                    }
                }.frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Routes").font(.headline)
                    TextField("Find endpoint", text: $filter).textFieldStyle(.roundedBorder)
                    List(selection: $selected) {
                        ForEach(fixture.edges.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { edge in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(edge.name).font(.system(size: 12))
                                Text("\(edge.count) connections · \(ByteCountFormatter.string(fromByteCount: edge.bytes, countStyle: .binary))")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }.tag(edge.id)
                        }
                    }.listStyle(.plain)
                    Text("All \(fixture.total) connections accounted for.").font(.system(size: 11, weight: .medium))
                    Text("\(fixture.unlocated) connections have no location. Curves show endpoint relationships, not measured router hops.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Natural Earth · Public domain\nLocal assets · No tile service").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(14).frame(minWidth: 250, idealWidth: 280, maxWidth: 310)
            }
            HStack {
                Text(renderer == 0 ? metrics : "Native Canvas · deterministic projection · drag to pan, pinch to zoom")
                Spacer()
                Text("No core / No proxy / No live connections")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(10)
        }
        .background(dark ? Color(red: 0.09, green: 0.11, blue: 0.15) : Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(dark ? .dark : .light)
        .onChange(of: scenario) { _, _ in selected = nil; send("all") }
    }
    func send(_ value: String) { command = value; commandRevision += 1 }
    func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 17, weight: .medium)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
struct MapWebView: NSViewRepresentable {
    let assets: URL
    let scenario: Int
    let dark: Bool
    @Binding var selected: String?
    let command: String
    let revision: Int
    @Binding var metrics: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "metrics")
        config.userContentController.add(context.coordinator, name: "selection")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        let html = try! String(contentsOf: assets.appendingPathComponent("index.html"), encoding: .utf8)
        web.loadHTMLString(html, baseURL: assets)
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        let state = "\(scenario)|\(dark)|\(selected ?? "")"
        if context.coordinator.state != state {
            context.coordinator.state = state
            let id = selected.map { "\"\($0)\"" } ?? "null"
            web.evaluateJavaScript("window.update?.(\(scenario),\(dark),\(id))")
        }
        if context.coordinator.revision != revision {
            context.coordinator.revision = revision
            web.evaluateJavaScript("window.command?.('\(command)')")
        }
    }
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MapWebView
        var state = ""
        var revision = -1
        init(_ parent: MapWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.metrics = error.localizedDescription }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.metrics = error.localizedDescription }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.metrics = "Page loaded; starting WebGL…"
            webView.evaluateJavaScript("window.update?.(\(parent.scenario),\(parent.dark),null)")
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }
            if message.name == "selection" { parent.selected = text } else { parent.metrics = text }
        }
    }
}

struct NativeMap: View {
    let polygons: [[[Double]]]
    let edges: [Edge]
    let dark: Bool
    @Binding var selected: String?
    let command: String
    let revision: Int
    let scenario: Int
    @State private var center = CGPoint(x: 0, y: 0)
    @State private var zoom: CGFloat = 1
    @State private var worldOnly = true
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnify: CGFloat = 1
    func projected(_ p: [Double]) -> CGPoint {
        let lat = min(85, max(-85, p[1])) * .pi / 180
        return CGPoint(x: p[0], y: -log(tan(.pi / 4 + lat / 2)) * 180 / .pi)
    }
    var body: some View {
        GeometryReader { geo in
            let base = min((geo.size.width - 40) / 360, (geo.size.height - 40) / 360)
            let scale = base * zoom * magnify
            let origin = CGPoint(x: geo.size.width/2 + drag.width, y: geo.size.height/2 + drag.height)
            Canvas { context, _ in
                func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x-center.x)*scale+origin.x, y: (p.y-center.y)*scale+origin.y) }
                let land = dark ? Color(red: 0.16, green: 0.20, blue: 0.25) : Color(red: 0.89, green: 0.91, blue: 0.93)
                for ring in polygons {
                    for wrap in (worldOnly ? 0...0 : -2...2) {
                        var path = Path()
                        for (i,p) in ring.enumerated() {
                            var point = projected(p); point.x += Double(wrap)*360
                            if i == 0 { path.move(to: screen(point)) } else { path.addLine(to: screen(point)) }
                        }
                        path.closeSubpath()
                        context.fill(path, with: .color(land))
                        context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.4)
                    }
                }
                for edge in edges.sorted(by: { $0.id != selected && $1.id == selected }) {
                    for wrap in (worldOnly ? 0...0 : -2...2) {
                        var path = Path()
                        for (i,p) in edge.points.enumerated() {
                            var point = projected(p); point.x += Double(wrap)*360
                            if i == 0 { path.move(to: screen(point)) } else { path.addLine(to: screen(point)) }
                        }
                        context.stroke(path, with: .color(edge.id == selected ? .orange : (dark ? Color(red:0.47,green:0.66,blue:0.90) : .blue).opacity(selected == nil ? 0.52 : 0.12)), lineWidth: edge.id == selected ? 2.5 : 1.2)
                        for p in [edge.points.first!,edge.points.last!] {
                            var point = projected(p); point.x += Double(wrap)*360
                            let q = screen(point)
                            context.fill(Path(ellipseIn: CGRect(x:q.x-3,y:q.y-3,width:6,height:6)),with:.color(.blue))
                        }
                    }
                }
            }
            .background(dark ? Color(red:0.09,green:0.11,blue:0.15) : Color(red:0.965,green:0.97,blue:0.98))
            .clipped()
            .gesture(DragGesture().updating($drag) { value,state,_ in state=value.translation }.onEnded { value in center.x -= value.translation.width/scale; center.y -= value.translation.height/scale })
            .simultaneousGesture(MagnifyGesture().updating($magnify) { value,state,_ in state=value.magnification }.onEnded { value in zoom=min(32,max(0.25,zoom*value.magnification)) })
            .onChange(of: revision) { _,_ in fit(size: geo.size) }
            .onChange(of: scenario) { _,_ in fit(size: geo.size) }
            .onAppear { fit(size: geo.size) }
            .accessibilityLabel("World route map. Use the route list to select and inspect all connections.")
        }
    }
    func fit(size: CGSize) {
        if command == "in" { zoom=min(32,zoom*1.4);return }
        if command == "out" { zoom=max(0.25,zoom/1.4);return }
        if command == "world" { center = .zero;zoom=1;worldOnly=true;return }
        worldOnly=false
        let visible = command == "selection" ? edges.filter { $0.id == selected } : edges
        let points = visible.flatMap(\.points)
        guard !points.isEmpty else { return }
        let xs = points.map { ($0[0].truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360) }.sorted()
        var gap = -Double.infinity; var cut = xs[0]
        for i in xs.indices {
            let next = i == xs.count-1 ? xs[0]+360 : xs[i+1]
            if next-xs[i] > gap { gap=next-xs[i];cut=next.truncatingRemainder(dividingBy:360) }
        }
        let normalized = points.map { p -> CGPoint in
            var q=projected(p);q.x=(q.x.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)
            if q.x < cut { q.x += 360 };return q
        }
        let minX=normalized.map(\.x).min()!,maxX=normalized.map(\.x).max()!
        let minY=normalized.map(\.y).min()!,maxY=normalized.map(\.y).max()!
        center=CGPoint(x:(minX+maxX)/2,y:(minY+maxY)/2)
        let base=min((size.width-40)/360,(size.height-40)/360)
        zoom=min(32,max(0.25,min((size.width-100)/max(20,maxX-minX),(size.height-100)/max(20,maxY-minY))/base))
    }
}
