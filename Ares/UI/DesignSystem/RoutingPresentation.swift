import SwiftUI

struct RoutingPresentation: View {
    let snapshot: RouteSnapshot
    let status: String
    @Environment(\.colorScheme) private var scheme
    @State private var selection: String?
    @State private var query = ""
    @State private var command = "world"
    @State private var revision = 0
    @State private var mapError: String?
    @State private var showInspector = true
    private var selected: ObservedRoute? { snapshot.routes.first { $0.id == selection } }
    private var filtered: [ObservedRoute] {
        snapshot.routes.filter { query.isEmpty || ([$0.application,$0.host,$0.rule]+$0.chain).contains { $0.localizedCaseInsensitiveContains(query) } }
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                TextField("Search route list",text:$query).textFieldStyle(.roundedBorder).frame(maxWidth:230)
                Spacer(minLength:8)
                Button { send("world") } label: { Image(systemName:"globe") }.help("World view")
                Button { send("all") } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }.help("Fit all located endpoints")
                Button { send("selection") } label: { Image(systemName:"scope") }.help("Focus selected route").disabled(selected?.hasLocation != true)
                Button { send("out") } label: { Image(systemName:"minus") }.help("Zoom out")
                Button { send("in") } label: { Image(systemName:"plus") }.help("Zoom in")
                Button { showInspector.toggle() } label: { Image(systemName:"sidebar.right") }.help("Show route details")
            }.buttonStyle(.borderless).controlSize(.small).padding(12)
            HSplitView {
                ZStack(alignment:.bottomLeading) {
                    RoutingMapSurface(snapshot:snapshot,selection:$selection,dark:scheme == .dark,command:command,revision:revision,error:$mapError)
                    if let mapError {
                        ContentUnavailableView("Map unavailable",systemImage:"map",description:Text(mapError))
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                    } else if snapshot.routes.isEmpty {
                        ContentUnavailableView("No active connections",systemImage:"network",description:Text(status.isEmpty ? "Routes appear when applications connect." : status))
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                    if !snapshot.routes.isEmpty && snapshot.unlocatedCount == snapshot.connectionCount {
                        ContentUnavailableView("Locations unavailable",systemImage:"mappin.slash",description:Text("Connections are listed on the right. Public IP locations are not available in the local database."))
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                    VStack(alignment:.leading,spacing:3) {
                        if !status.isEmpty && !snapshot.routes.isEmpty { Text(status).foregroundStyle(.orange) }
                        Text("Dashed lines: endpoint associations · not measured network hops")
                        Text("IP locations are estimates · Natural Earth / MapLibre")
                    }.font(.system(size:10)).foregroundStyle(.secondary).padding(8)
                        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:6)).padding(10)
                }.frame(minWidth:300,maxWidth:.infinity,maxHeight:.infinity).clipped()
                if showInspector { inspector.frame(minWidth:235,idealWidth:280,maxWidth:340) }
            }
        }
        .background(DS.canvas)
        .clipShape(RoundedRectangle(cornerRadius:DS.Radius.card))
        .padding(.horizontal,DS.Space.lg).padding(.top,DS.Space.pageTop).padding(.bottom,DS.Space.lg)
        .toolbar {
            ToolbarItem(placement:.navigation) {
                HStack(spacing:20) {
                    VStack(alignment:.leading,spacing:1) {
                        Text("Routing").font(.system(size:13,weight:.semibold))
                        Text("Connections").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                    metric(snapshot.connectionCount,"connections")
                    metric(snapshot.unlocatedCount,"unlocated").help("Connections with no located endpoints. Other connections may still have unknown segments.")
                }.padding(.leading,16)
            }.aresUnframed()
        }
        .onChange(of:snapshot.routes.map(\.id)) { _, ids in if let selection, !ids.contains(selection) { self.selection=nil } }
    }
    private var inspector: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack { Text("Routes").font(.system(size:13,weight:.semibold));Spacer();Text("\(filtered.count) / \(snapshot.routes.count)").font(.system(size:11)).foregroundStyle(.secondary) }.padding(12)
            List(selection:$selection) {
                ForEach(filtered) { route in
                    VStack(alignment:.leading,spacing:4) {
                        Text(route.host.isEmpty ? "Unknown destination" : route.host).font(.system(size:12,weight:.medium)).lineLimit(1)
                        Text("\(route.application) · \(route.connections) connections").font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    }.tag(route.id)
                }
            }.listStyle(.plain).frame(minHeight:100)
            if let selected {
                Divider()
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        Text(selected.application).font(.system(size:13,weight:.semibold))
                        Text("↓ \(bytes(selected.download))   ↑ \(bytes(selected.upload))")
                            .font(.system(size:12)).monospacedDigit()
                        Text("Active connection totals").font(.system(size:10)).foregroundStyle(.secondary)
                        ForEach(selected.endpoints.indices,id:\.self) { index in
                            let endpoint=selected.endpoints[index]
                            HStack(alignment:.top,spacing:8) {
                                Image(systemName:icon(endpoint.kind)).frame(width:16).foregroundStyle(.secondary)
                                VStack(alignment:.leading,spacing:3) {
                                    Text(endpoint.name).font(.system(size:12,weight:.medium)).textSelection(.enabled)
                                    if !endpoint.address.isEmpty { Text(endpoint.address).font(.system(size:11,design:.monospaced)).textSelection(.enabled) }
                                    Text(endpoint.evidence).font(.system(size:10)).foregroundStyle(.secondary)
                                    Text(endpoint.location.map { "\($0.label) · \($0.precision)" } ?? "Location unavailable")
                                        .font(.system(size:10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Divider()
                        Text("Core chain").font(.system(size:11,weight:.semibold))
                        Text(selected.chain.isEmpty ? "Not reported" : selected.chain.joined(separator:" → "))
                            .font(.system(size:11)).textSelection(.enabled)
                        Text("Core-reported order; groups are not geographic hops. Rule: \(selected.rule)")
                            .font(.system(size:10)).foregroundStyle(.secondary)
                    }.padding(12)
                }.frame(maxHeight:340)
            } else {
                Text("Select a route to inspect its observed chain and location sources.").font(.system(size:11)).foregroundStyle(.secondary).padding(12)
            }
        }
    }
    private func send(_ value:String) { command=value;revision+=1 }
    private func bytes(_ value:Int64)->String { ByteCountFormatter.string(fromByteCount:value,countStyle:.binary) }
    private func icon(_ kind:String)->String {
        switch kind { case "application": return "app";case "proxy":return "server.rack";case "destination":return "globe";default:return "questionmark.circle" }
    }
    private func metric(_ count:Int,_ unit:String)->some View {
        HStack(alignment:.firstTextBaseline,spacing:4) {
            Text("\(count)").font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit()
            Text(unit).font(.system(size:11)).foregroundStyle(.secondary)
        }.fixedSize()
    }
}
