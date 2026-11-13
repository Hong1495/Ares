import SwiftUI
import SubscriptionKit

struct LocalRulesEditorView: View {
    private struct EditingRule: Identifiable {
        let id = UUID()
        let lineID: UUID?
        let raw: String
    }
    @State private var document: RuleDraftDocument
    @State private var source: String
    @State private var sourceMode = false
    @State private var selection: UUID?
    @State private var editing: EditingRule?
    @State private var applying = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    let revision: String
    let initialRules: String

    init(initialRules: String, revision: String) {
        self.initialRules = initialRules; self.revision = revision
        _document = State(initialValue: RuleDraftDocument(initialRules))
        _source = State(initialValue: initialRules)
    }
    private var selectedIndex: Int? { document.rules.firstIndex { $0.id == selection } }
    private var warning: String? {
        let rules = document.rules
        if let index = rules.firstIndex(where: { $0.rule?.hasPrefix("MATCH,") == true }), index < rules.count - 1 {
            return "Rules below MATCH cannot be reached. Local MATCH also takes precedence over subscription rules."
        }
        if rules.contains(where: { $0.rule?.hasPrefix("MATCH,") == true }) {
            return "Local MATCH takes precedence over all subscription rules."
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text("Local Rules").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Picker("Editor", selection: $sourceMode) {
                    Text("List").tag(false)
                    Text("Source").tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 150).fixedSize()
                Spacer()
                Button("Cancel") { dismiss() }.fixedSize()
                Button("Save & Apply") { apply() }.buttonStyle(.borderedProminent).fixedSize()
            }.controlSize(.small).fixedSize(horizontal: false, vertical: true).padding(DS.Space.lg).disabled(applying)
            Divider()
            if sourceMode {
                TextEditor(text: $source).font(DS.Typography.metadata.monospaced())
                    .padding(DS.Space.md).disabled(applying)
            } else {
                HStack(spacing: DS.Space.md) {
                    Text("\(document.rules.count) Rules").font(DS.Typography.metadata).foregroundStyle(.secondary)
                    Spacer()
                    Button { editing = EditingRule(lineID: nil, raw: "DOMAIN-SUFFIX,,DIRECT") } label: { Image(systemName: "plus") }
                        .help("Add rule").accessibilityLabel("Add rule")
                    Button { editSelected() } label: { Image(systemName: "pencil") }
                        .disabled(selection == nil).help("Edit rule").accessibilityLabel("Edit rule")
                    Button { if let selection { document.move(id: selection, by: -1) } } label: { Image(systemName: "arrow.up") }
                        .disabled(selectedIndex == nil || selectedIndex == 0).help("Move up").accessibilityLabel("Move rule up")
                    Button { if let selection { document.move(id: selection, by: 1) } } label: { Image(systemName: "arrow.down") }
                        .disabled(selectedIndex == nil || selectedIndex == document.rules.count - 1).help("Move down").accessibilityLabel("Move rule down")
                    Button { if let selection { document.remove(id: selection); self.selection = nil } } label: { Image(systemName: "minus") }
                        .disabled(selection == nil).help("Remove rule").accessibilityLabel("Remove rule")
                }.buttonStyle(.borderless).padding(DS.Space.md).disabled(applying)
                Table(document.rules, selection: $selection) {
                    TableColumn("Order") { line in
                        Text(String((document.rules.firstIndex { $0.id == line.id } ?? 0) + 1))
                            .font(DS.Typography.metadata.monospacedDigit()).foregroundStyle(.secondary)
                    }.width(48)
                    TableColumn("Rule") { line in
                        Text(line.rule ?? "").font(DS.Typography.metadata.monospaced())
                            .lineLimit(1).truncationMode(.middle).help(line.rule ?? "")
                    }
                    TableColumn("") { line in
                        Button {
                            editing = EditingRule(lineID: line.id, raw: line.rule ?? "")
                        } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).accessibilityLabel("Edit \(line.rule ?? "rule")")
                    }.width(28)
                }.disabled(applying)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                if let error { Text(error).foregroundStyle(Color.statusBad) }
                if !sourceMode, let warning { Text(warning).foregroundStyle(Color.statusWarn) }
                Text("Local rules run first, in order. Comments and advanced syntax are preserved in Source.")
                    .foregroundStyle(.secondary)
            }.font(DS.Typography.metadata).frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.lg)
        }
        .frame(minWidth: 720, minHeight: 490).background(DS.canvas)
        .interactiveDismissDisabled(applying)
        .onChange(of: sourceMode) { _, isSource in
            if isSource { source = document.text }
            else { document = RuleDraftDocument(source); selection = nil }
        }
        .sheet(item: $editing) { item in
            RuleEditForm(raw: item.raw, isNew: item.lineID == nil) { result in
                if let id = item.lineID { document.replace(id: id, with: result) }
                else { document.append(result) }
            }
        }
    }
    private func editSelected() {
        guard let line = document.rules.first(where: { $0.id == selection }) else { return }
        editing = EditingRule(lineID: line.id, raw: line.rule ?? "")
    }
    private func apply() {
        let text = sourceMode ? source : document.text
        applying = true; error = nil
        Task { @MainActor in
            if await LocalRulesService.apply(text, expectedRevision: revision, expectedRules: initialRules) { dismiss() }
            else { error = AppState.shared.lastOperationError ?? "Another operation is in progress. Try again." }
            applying = false
        }
    }
}

private struct RuleEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var form: RuleForm
    @State private var raw: String
    @State private var useSource: Bool
    private let formSupported: Bool
    let save: (String) -> Void

    init(raw: String, isNew: Bool, save: @escaping (String) -> Void) {
        let parsed = RuleForm(raw)
        formSupported = isNew || parsed != nil
        _form = State(initialValue: parsed ?? RuleForm())
        _raw = State(initialValue: raw)
        _useSource = State(initialValue: !formSupported)
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack {
                Text("Edit Rule").font(DS.Typography.secondary.weight(.semibold)).fixedSize()
                Spacer()
                Button("Cancel") { dismiss() }.fixedSize()
                Button("Done") { save(useSource ? raw : form.serialized); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(useSource ? raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || raw.contains("\n") : form.validationError != nil)
            }.controlSize(.small)
            if useSource {
                TextField("Rule expression", text: $raw).font(DS.Typography.metadata.monospaced()).textFieldStyle(.roundedBorder)
                Text("The complete expression is preserved. The core validates it when you apply the draft.")
                    .font(DS.Typography.metadata).foregroundStyle(.secondary)
            } else {
                Form {
                    Picker("Type", selection: $form.type) {
                        ForEach(RuleForm.types, id: \.self) { Text($0).tag($0) }
                    }
                    if form.type != "MATCH" { TextField("Value", text: $form.payload) }
                    TextField("Policy", text: $form.target)
                    if form.allowsNoResolve { Toggle("Do not resolve domain names", isOn: $form.noResolve) }
                }.formStyle(.grouped)
                if let error = form.validationError { Text(error).font(DS.Typography.metadata).foregroundStyle(.secondary) }
                Text(form.serialized).font(DS.Typography.metadata.monospaced()).textSelection(.enabled)
                Button("Edit expression") { raw = form.serialized; useSource = true }.controlSize(.small)
            }
        }.padding(DS.Space.lg).frame(width: 580).background(DS.canvas)
    }
}
