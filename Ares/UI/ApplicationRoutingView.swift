import SwiftUI
import AppKit
import SubscriptionKit

struct ApplicationRoutingView: View {
    var embedded = false
    var initialPaths: [String] = []
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var controller = ClashController.shared
    @State private var snapshot: ApplicationRoutingService.Snapshot?
    @State private var paths: [String] = []
    @State private var selection = Set<String>()
    @State private var target = "DIRECT"
    @State private var live: [Connection] = []
    @State private var capturedAt: Date?
    @State private var search = ""
    @State private var error: String?
    @State private var message: String?
    @State private var busy = false
    @State private var undo: ApplicationRoutingService.Undo?
    private var selected: [String] { selection.sorted() }
    private var matching: [Connection] { live.filter { selection.contains($0.metadata.processPath ?? "") } }
    var body: some View {
        VStack(spacing: 0) {
            if !embedded || undo != nil { HStack {
                if !embedded { Text("Application Routing").font(DS.Typography.secondary.weight(.semibold)) }
                Spacer()
                if let undo { Button("Undo Last Change") { Task { await revert(undo) } } }
                if !embedded { Button("Done") { dismiss() } }
            }.controlSize(.small).padding(DS.Space.lg) }
            HSplitView {
                VStack(spacing: DS.Space.md) {
                    HStack {
                        TextField("Search executables", text: $search).textFieldStyle(.roundedBorder)
                        Button { chooseApplication() } label: { Image(systemName: "plus") }.help("Choose an application or executable")
                    }.controlSize(.small)
                    List(paths.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self, selection: $selection) { path in
                        VStack(alignment: .leading, spacing: 3) {
                            Text((path as NSString).lastPathComponent).font(DS.Typography.secondary)
                            Text(path).font(DS.Typography.metadata).foregroundStyle(.secondary).lineLimit(2).help(path)
                        }.padding(.vertical, 3)
                    }
                    Text("Exact executables · Select observed helper processes separately. Unknown and remote processes are not inferred.")
                        .font(DS.Typography.metadata).foregroundStyle(.secondary)
                }.padding(DS.Space.lg).frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                ScrollView { VStack(alignment: .leading, spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Picker("Route", selection: $target) {
                            ForEach(snapshot?.targets ?? ["DIRECT", "REJECT"], id: \.self) { name in
                                Text(name == "DIRECT" ? "Direct" : name == "REJECT" ? "Block" : name).tag(name)
                            }
                        }.frame(maxWidth: 320)
                        HStack {
                        Button("Use Subscription") { apply(nil) }.disabled(selected.isEmpty || snapshot == nil)
                        Button("Apply Route") { apply(target) }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || snapshot == nil)
                        }
                    }.controlSize(.small)
                    Text("Local rules apply across subscriptions, to new connections in Rule mode. Existing connections keep their route; reconnect the application to verify. Removing a local rule restores normal rule evaluation.")
                        .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    if let snapshot, !selected.isEmpty {
                        let existing = RuleDraftDocument(snapshot.rules).rules.compactMap { $0.rule.flatMap(RuleForm.init) }.filter { $0.type == "PROCESS-PATH" && selection.contains($0.payload) }
                        let conflicts = Dictionary(grouping: existing, by: \.payload).values.filter { $0.count > 1 }.count
                        if conflicts > 0 { Text("\(conflicts) executable(s) have duplicate local rules. Apply Route replaces their exact-path entries with one rule each.").font(DS.Typography.metadata).foregroundStyle(Color.statusWarn) }
                    }
                    if AppState.shared.currentMode != .rule {
                        Text("Rule mode is not active. Application rules are saved but bypassed in Global / Direct mode.").font(DS.Typography.metadata).foregroundStyle(Color.statusWarn)
                    }
                    Text("Rule precedence").font(DS.Typography.secondary.weight(.medium))
                    Text(snapshot?.evidenceSource ?? "Loading configuration…").font(DS.Typography.metadata).foregroundStyle(.secondary)
                    Table(ApplicationRouting.evidence(paths: selected, rules: snapshot?.evidence ?? [])) {
                        TableColumn("Order") { Text(String($0.order)).monospacedDigit() }.width(48)
                        TableColumn("Rule") { Text($0.expression).lineLimit(1).help($0.expression) }
                        TableColumn("Match / conflict") { Text($0.explanation).lineLimit(2) }.width(min: 150, ideal: 190)
                    }.font(DS.Typography.metadata).frame(minHeight: 120)
                    Text("Local exact-path rules are placed first. Other domain/IP rules may also match; advanced rules are not simulated here. The connection table below reports the core’s actual decision.")
                        .font(DS.Typography.metadata).foregroundStyle(.secondary)
                    HStack {
                        Text("Observed connections").font(DS.Typography.secondary.weight(.medium))
                        Spacer()
                        Text(capturedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "Not read").foregroundStyle(.secondary)
                        Button { Task { await readConnections() } } label: { Image(systemName: "arrow.clockwise") }.help("Read core connections")
                    }.font(DS.Typography.metadata).controlSize(.small)
                    Table(matching) {
                        TableColumn("Destination") { Text($0.metadata.host.isEmpty ? $0.destinationString : $0.metadata.host).lineLimit(1) }
                        TableColumn("Matched rule") { Text($0.rule + ": " + $0.rulePayload).lineLimit(1).help($0.rule + ": " + $0.rulePayload) }
                        TableColumn("Actual route") { Text($0.chainsString).lineLimit(1).help($0.chainsString) }
                        TableColumn("↓ / ↑") { Text(bytes($0.download) + " / " + bytes($0.upload)).monospacedDigit() }.width(110)
                    }.font(DS.Typography.metadata).frame(minHeight: 120)
                    if matching.isEmpty { Text("No matching core-reported executable. Process routing requires core process identification; unavailable identity may require privileged/TUN mode. Blocked or closed connections may not appear.").font(DS.Typography.metadata).foregroundStyle(.secondary) }
                }.padding(DS.Space.lg).frame(minHeight: 640) }.frame(minWidth: 440)
            }
            if let message { Text(message).font(DS.Typography.metadata).foregroundStyle(.secondary).padding(.horizontal, DS.Space.lg) }
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad).padding(DS.Space.md) }
        }.frame(minWidth: embedded ? 0 : 940, minHeight: embedded ? 0 : 680).background(DS.canvas).scrollIndicators(.never, axes: [.horizontal, .vertical])
            .disabled(busy).interactiveDismissDisabled(busy)
            .onChange(of: controller.runtimeGeneration) { _, _ in live = []; capturedAt = nil }
            .task { paths = initialPaths.filter(ApplicationRouting.validPath).sorted(); selection = Set(paths); await load(); await readConnections() }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) }
    private func chooseApplication() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.compactMap { url -> String? in
            let path = url.pathExtension == "app" ? Bundle(url: url)?.executableURL?.path : url.path
            return path.flatMap { ApplicationRouting.validPath($0) ? $0 : nil }
        }
        paths = Array(Set(paths + chosen)).sorted(); selection = Set(chosen)
    }
    private func load() async {
        do {
            let result = try await ApplicationRoutingService.load(); snapshot = result
            paths = Array(Set(paths + ApplicationRouting.paths(in: result.rules))).sorted()
            if !result.targets.contains(target) { target = "DIRECT" }
        } catch { self.error = "Configuration could not be read. Reopen after the current operation finishes." }
    }
    private func readConnections() async {
        do {
            live = try await ApplicationRoutingService.connections(); capturedAt = Date()
            paths = Array(Set(paths + live.compactMap { $0.metadata.processPath }.filter(ApplicationRouting.validPath))).sorted()
        } catch { live = []; capturedAt = nil; message = "Runtime connection evidence unavailable. Saved rules remain editable." }
    }
    private func apply(_ target: String?) {
        guard let snapshot else { return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                undo = try await ApplicationRoutingService.apply(paths: selected, target: target, snapshot: snapshot)
                message = "Saved and validated. Reconnect the application, then read connections to confirm the actual rule and route."
                await load(); await readConnections()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func revert(_ value: ApplicationRoutingService.Undo) async {
        busy = true; defer { busy = false }
        if await ApplicationRoutingService.undo(value) { undo = nil; message = "Previous local rules restored."; await load(); await readConnections() }
        else { error = AppState.shared.lastOperationError ?? "Undo is unavailable after another rule edit." }
    }
}
