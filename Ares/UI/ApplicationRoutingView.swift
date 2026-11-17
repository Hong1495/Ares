import SwiftUI
import AppKit
import Combine
import SubscriptionKit

struct ApplicationRoutingView: View {
    var embedded = false
    var initialPaths: [String] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var controller = ClashController.shared
    @ObservedObject private var appState = AppState.shared
    @StateObject private var model = ApplicationRoutingViewModel()
    @State private var search = ""
    @State private var showingDiscovery = false
    @State private var showingExecutables = false
    @State private var showingEvidence = false

    private var ruleMode: Bool { appState.currentMode == .rule }
    private var rows: [ApplicationRoutingPresentation.Application] {
        model.applications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.paths.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                HStack { Text("Applications").font(DS.Typography.secondary.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
                    .controlSize(.small).padding(DS.Space.lg)
            }
            CollectionTools(placeholder: "Search applications", search: $search) {
                Button { showingDiscovery = true } label: { Image(systemName: "plus") }
                    .help("Add application route").accessibilityLabel("Add application route")
                Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload configuration and connections").accessibilityLabel("Reload application routes")
                Button { Task { await model.revert() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(model.undo == nil).help("Undo last route change").accessibilityLabel("Undo last route change")
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                    .help("Local application routes apply across subscriptions in Rule mode. Each selected executable is matched exactly; helpers are never included implicitly. Existing connections keep their original route.")
            }.disabled(model.busy)

            DSCard(padding: 0, spacing: 0) {
                if let app = model.selectedApplication {
                    editor(app).padding(DS.Space.lg)
                }
                applicationTable
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.lg)
            if let error = model.error {
                Text(error).foregroundStyle(Color.statusBad).font(DS.Typography.metadata)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.md)
            }
        }
        .background(DS.canvas).font(DS.Typography.secondary)
        .frame(minWidth: embedded ? 0 : 680, minHeight: embedded ? 0 : 540)
        .scrollIndicators(.never, axes: [.horizontal, .vertical])
        .interactiveDismissDisabled(model.busy)
        .sheet(isPresented: $showingDiscovery) { discovery }
        .onChange(of: controller.runtimeGeneration) { _, _ in
            model.invalidateRuntime()
            Task { await model.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { _ in
            Task { await model.reload() }
        }
        .task {
            await model.start(paths: initialPaths)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                if scenePhase == .active { await model.readConnections() }
            }
        }
    }

    private var applicationTable: some View {
        Table(rows, selection: Binding(get: { model.selectedAppID }, set: {
            model.select($0); showingEvidence = false
            showingExecutables = (model.selectedApplication?.paths.count ?? 0) > 1
        })) {
            TableColumn("Application") { app in
                HStack(spacing: 8) {
                    ApplicationRouteIcon(path: app.iconPath)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(DS.Typography.body.weight(.medium)).lineLimit(1)
                        Text("\(app.paths.count) executable\(app.paths.count == 1 ? "" : "s")")
                            .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }.width(min: 160, ideal: 240)
            TableColumn("Route") { app in
                Text(ApplicationRoutingPresentation.routeLabel(model.route(paths: app.paths)))
                    .lineLimit(1).help(routeHelp(app))
            }.width(min: 110, ideal: 160)
            TableColumn("Verification") { app in
                verificationLabel(model.verification(paths: app.paths, ruleMode: ruleMode))
            }.width(160)
        }
        .disabled(model.busy)
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No application routes" : "No matching applications", systemImage: search.isEmpty ? "app.connected.to.app.below.fill" : "magnifyingglass")
                } description: {
                    Text(search.isEmpty ? "Add an application to choose its route. Other applications follow your existing rules." : "Try another name or executable path.")
                } actions: {
                    if search.isEmpty { Button("Add Application…") { showingDiscovery = true }.disabled(model.busy) }
                }
            }
        }
        .accessibilityLabel("Application routing rules")
        .frame(minHeight: 180)
    }

    private func editor(_ app: ApplicationRoutingPresentation.Application) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(app.name).font(DS.Typography.body.weight(.medium)).lineLimit(1)
                    Button { showingExecutables.toggle() } label: {
                        HStack(spacing: DS.Space.xs) {
                            Text("\(model.selectedPaths.count) of \(app.paths.count) executables")
                            Image(systemName: showingExecutables ? "chevron.up" : "chevron.down")
                        }.font(DS.Typography.metadata).foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                        .help("Review the exact executables that will change")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Picker("Route", selection: $model.target) {
                    Text("Follow rules").tag(ApplicationRouting.SelectionRoute.inherited)
                    if model.target == .mixed { Text("Mixed").tag(ApplicationRouting.SelectionRoute.mixed) }
                    ForEach(routeTargets, id: \.self) { name in
                        Text(ApplicationRoutingPresentation.routeLabel(.target(name))).tag(ApplicationRouting.SelectionRoute.target(name))
                    }
                }.labelsHidden().frame(width: 180)
                    .disabled(model.selectedPaths.isEmpty || model.snapshot == nil)
                Button("Apply") { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent).disabled(!model.canApply)
                Button { showingEvidence.toggle() } label: {
                    Image(systemName: showingEvidence ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                }.buttonStyle(.borderless).help("Inspect rule and connection evidence").accessibilityLabel("Inspect routing evidence")
            }.controlSize(.small).disabled(model.busy)

            if !ruleMode { Text("Rules are bypassed in Global / Direct mode.").foregroundStyle(Color.statusWarn).font(DS.Typography.metadata) }
            if let message = model.message { Text(message).font(DS.Typography.metadata).foregroundStyle(.secondary) }

            if showingExecutables || showingEvidence {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        if showingExecutables { executableList(app) }
                        if showingEvidence { evidence }
                    }
                }.frame(height: showingEvidence ? 180 : min(160, CGFloat(app.paths.count) * 38 + 28))
            }
        }
    }

    private var routeTargets: [String] {
        var targets = model.snapshot?.targets ?? ["DIRECT", "REJECT"]
        if case .target(let selected) = model.target, !targets.contains(selected) { targets.append(selected) }
        return targets
    }

    private func executableList(_ app: ApplicationRoutingPresentation.Application) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(app.paths, id: \.self) { path in
                HStack(alignment: .top, spacing: 8) {
                    Toggle(isOn: Binding(get: { model.selectedPaths.contains(path) }, set: { model.setPath(path, included: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text((path as NSString).lastPathComponent).lineLimit(1)
                            Text(path).font(DS.Typography.metadata).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle).help(path).textSelection(.enabled)
                        }
                    }.toggleStyle(.checkbox)
                    Spacer(minLength: 8)
                    Text(ApplicationRoutingPresentation.routeLabel(model.route(paths: [path]))).foregroundStyle(.secondary)
                }
            }
            Text("Only checked executables will change.")
                .font(DS.Typography.metadata).foregroundStyle(.secondary)
                .help("Additional helpers may appear when the application opens new connections. App grouping never silently expands an exact-path rule.")
        }.disabled(model.busy)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text("Connection evidence").fontWeight(.medium)
                Spacer()
                Text(model.capturedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "Unavailable").foregroundStyle(.secondary)
            }
            if model.matching.isEmpty {
                Text("No matching connection observed. Open a new connection in the application to verify.").foregroundStyle(.secondary)
            } else {
                ForEach(model.matching) { connection in
                    HStack(spacing: 12) {
                        Text(connection.metadata.host.isEmpty ? connection.destinationString : connection.metadata.host).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(connection.rule + ": " + connection.rulePayload).lineLimit(1).help(connection.rulePayload)
                        Text(connection.chainsString).lineLimit(1).help(connection.chainsString)
                    }
                }
            }
            DisclosureGroup("Rule details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.snapshot?.evidenceSource ?? "Unavailable").foregroundStyle(.secondary)
                    ForEach(ApplicationRouting.evidence(paths: model.selectedPaths.sorted(), rules: model.snapshot?.evidence ?? [])) { row in
                        Text("\(row.order). \(row.expression)").textSelection(.enabled).help(row.explanation)
                    }
                }.padding(.top, 6)
            }
        }.font(DS.Typography.metadata)
    }

    private var discovery: some View {
        ApplicationDiscoverySheet(applications: model.discovered, reload: { await model.readConnections() },
            add: { model.add(paths: $0); showingExecutables = true }, browse: { chooseApplication() })
    }

    private func verificationLabel(_ status: ApplicationRouting.Verification) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status == .verified ? "checkmark.circle" : status == .different || status == .conflict ? "exclamationmark.circle" : "circle.dotted")
                .foregroundStyle(status == .verified ? Color.statusGood : status == .different || status == .conflict ? Color.statusWarn : Color.secondary)
                .accessibilityHidden(true)
            Text(status.rawValue).lineLimit(1)
        }.help("Verified requires a matching exact-path rule and route reported by the core. A saved rule or missing connection alone does not prove it is effective.")
    }

    private func routeHelp(_ app: ApplicationRoutingPresentation.Application) -> String {
        let count = app.paths.filter { ApplicationRouting.localRoutes(in: model.localRules)[$0] != nil }.count
        return "\(count) of \(app.paths.count) known executables have local overrides. Unconfigured executables follow existing rules."
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.compactMap { url in
            url.pathExtension == "app" ? Bundle(url: url)?.executableURL?.path : url.path
        }
        model.add(paths: paths); showingExecutables = true
    }
}

private struct ApplicationRouteIcon: View {
    let path: String?
    var body: some View {
        Group {
            if let path { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable() }
            else { Image(systemName: "app").resizable() }
        }.frame(width: 20, height: 20).accessibilityHidden(true)
    }
}

private struct ApplicationDiscoverySheet: View {
    let applications: [ApplicationRoutingPresentation.Application]
    let reload: () async -> Void
    let add: ([String]) -> Void
    let browse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection = Set<String>()
    private var rows: [ApplicationRoutingPresentation.Application] {
        applications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack { Text("Add Applications").font(DS.Typography.secondary.weight(.semibold)); Spacer(); Button("Cancel") { dismiss() } }
            HStack {
                TextField("Search discovered applications", text: $search).textFieldStyle(.roundedBorder)
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.help("Read core connections")
            }
            List(rows, selection: $selection) { app in
                HStack(spacing: 8) {
                    ApplicationRouteIcon(path: app.iconPath)
                    Text(app.name)
                    Spacer()
                    Text("\(app.paths.count) executable\(app.paths.count == 1 ? "" : "s")").foregroundStyle(.secondary).font(DS.Typography.metadata)
                }.tag(app.id)
            }.overlay {
                if rows.isEmpty { ContentUnavailableView("No discovered applications", systemImage: "app.dashed", description: Text("Open a connection in the application, or choose its executable.")) }
            }
            HStack {
                Button("Choose from Mac…") { dismiss(); browse() }
                Spacer()
                Button("Add Selected") {
                    add(applications.filter { selection.contains($0.id) }.flatMap(\.paths)); dismiss()
                }.buttonStyle(.borderedProminent).disabled(selection.isEmpty)
            }
        }.controlSize(.small).font(DS.Typography.secondary).padding(DS.Space.lg)
            .frame(width: 520, height: 420).scrollIndicators(.never)
    }
}
