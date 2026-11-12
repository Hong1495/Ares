import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @EnvironmentObject var profileService: ProfileService
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingFileImporter = false
    @State private var newProfileName = ""
    @State private var newProfileURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingProfile: Profile?
    @State private var editingRawProfile: Profile?

    private var filteredProfiles: [Profile] {
        profileService.profiles.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.url?.host?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView(.vertical) {
                if filteredProfiles.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No subscriptions" : "No matching subscriptions",
                        systemImage: "rectangle.stack",
                        description: Text(searchText.isEmpty ? "Use + to add a remote subscription or local file." : "Try another name or host.")
                    ).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 290), spacing: DS.Space.md)],
                        spacing: DS.Space.md
                    ) {
                        ForEach(filteredProfiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isActive: profileService.activeProfileID == profile.id,
                                onSelect: { profileService.setActiveProfile(id: profile.id) },
                                onEdit: { editingProfile = profile },
                                onEditRaw: { editingRawProfile = profile },
                                onDelete: { profileService.deleteProfile(id: profile.id) }
                            )
                        }
                    }.padding(DS.Space.lg)
                }
            }.scrollIndicators(.never)
        }
        .background(DS.canvas)
        .navigationTitle("")
        .toolbar { CollectionTitleToolbar(title: "Subscriptions", count: profileService.profiles.count, unit: "Profiles") }
        .sheet(isPresented: $showingAddSheet) {
            AddProfileSheet(
                name: $newProfileName,
                url: $newProfileURL,
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                onAdd: { Task { await addProfile() } },
                onCancel: {
                    showingAddSheet = false
                    newProfileName = ""
                    newProfileURL = ""
                    errorMessage = nil
                }
            )
        }
        .sheet(item: $editingProfile) { profile in
            EditProfileSheet(profile: profile) { name, url in
                try profileService.editProfile(id: profile.id, name: name, urlString: url)
            }
        }
        .sheet(item: $editingRawProfile) { profile in
            ProfileEditorView(profile: profile)
                .environmentObject(profileService)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.yaml, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        CollectionTools(placeholder: "Search subscriptions", search: $searchText) {
            Menu {
                Button("Remote Subscription") { showingAddSheet = true }
                Button("Local File") { showingFileImporter = true }
            } label: {
                Image(systemName: "plus").frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Add subscription or local file")
            .accessibilityLabel("Add subscription")
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else { return }
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            try profileService.addLocalProfile(name: fileName, fileURL: fileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addProfile() async {
        guard !newProfileName.isEmpty, !newProfileURL.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        guard let url = URL(string: newProfileURL) else {
            errorMessage = "Invalid URL"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await profileService.addRemoteProfile(name: newProfileName, url: url)
            showingAddSheet = false
            newProfileName = ""
            newProfileURL = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Card

struct ProfileCard: View {
    let profile: Profile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onEditRaw: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var clashViewModel: ClashViewModel
    @State private var isUpdating = false
    @EnvironmentObject var profileService: ProfileService

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header

            if profile.needsRuleResources == true {
                Label("Saved · Rule data requires a network connection before use", systemImage: "exclamationmark.circle")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(Color.statusWarn)
            }
            if let sub = profile.subscriptionInfo {
                usage(sub)
            }

            Spacer(minLength: 0)

            actions
        }
        .modifier(SubscriptionSurface(selected: isActive))
    }

    private var header: some View {
        SubscriptionHeading(name: profile.name,
                            source: profile.url?.host ?? "Local configuration",
                            remote: profile.type == .remote, selected: isActive)
    }

    private func usage(_ sub: SubscriptionInfo) -> some View {
        let fraction = sub.total > 0 ? min(Double(sub.used) / Double(sub.total), 1) : 0

        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(Self.formatBytes(sub.used))
                    .font(DS.Typography.secondary.weight(.semibold))
                    .monospacedDigit()
                Text("of \(Self.formatBytes(sub.total))")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if fraction > 0.9 {
                    DSTag(text: "NEAR LIMIT", tint: .statusBad)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(usageColor(fraction))
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 5)

            HStack(spacing: DS.Space.md) {
                if let expire = sub.expire {
                    Text("Expires \(expire.formatted(date: .abbreviated, time: .omitted))")
                }
                if let lastUpdated = profile.lastUpdated {
                    Text("Updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                }
                Spacer(minLength: 0)
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.tertiary)
        }

    }

    private var actions: some View {
        HStack(spacing: DS.Space.xs) {
            Button(action: onSelect) {
                Text(isActive
                     ? (profileService.isSwitchingProfile ? "Applying…" : (clashViewModel.isRunning ? "Apply again" : "Selected"))
                     : "Use profile")
                    .font(DS.Typography.metadata.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(profileService.isSwitchingProfile || clashViewModel.isToggling || (isActive && !clashViewModel.isRunning))

            if profile.type == .remote {
                ActionButton(icon: "arrow.clockwise", tooltip: "Update subscription") {
                    Task {
                        isUpdating = true
                        do { try await profileService.updateProfile(id: profile.id) }
                        catch is CancellationError { }
                        catch { AppState.shared.reportError(error.localizedDescription) }
                        isUpdating = false
                    }
                }
                .disabled(isUpdating)
            }

            ActionButton(icon: "pencil", tooltip: "Rename") { onEdit() }
            ActionButton(icon: "curlybraces", tooltip: "Edit configuration") { onEditRaw() }
            ActionButton(icon: "trash", tooltip: "Delete", color: .statusBad) { onDelete() }
        }
    }

    private func usageColor(_ fraction: Double) -> Color {
        if fraction > 0.9 { return .statusBad }
        if fraction > 0.7 { return .statusWarn }
        return .seriesDown
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

struct ActionButton: View {
    let icon: String
    let tooltip: String
    var color: Color = .secondary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isHovered ? color : Color.secondary)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? color.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sheets

struct AddProfileSheet: View {
    @Binding var name: String
    @Binding var url: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Remote Profile")
                    .font(DS.Typography.title.weight(.semibold))
                Text("Ares downloads the subscription and keeps it up to date.")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                TextField("Profile name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Subscription URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(Color.statusBad)
            }

            HStack(spacing: DS.Space.sm) {
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { onAdd() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || name.isEmpty || url.isEmpty)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 420)
    }
}

struct EditProfileSheet: View {
    let profile: Profile
    var onSave: (String, String) throws -> Void

    @State private var name: String
    @State private var url: String
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss

    init(profile: Profile, onSave: @escaping (String, String) throws -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _url = State(initialValue: profile.url?.absoluteString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("Edit Profile")
                .font(DS.Typography.title.weight(.semibold))

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                TextField("Profile name", text: $name)
                    .textFieldStyle(.roundedBorder)

                if case .remote = profile.type {
                    TextField("Subscription URL", text: $url)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text("Local profile paths cannot be edited")
                        .font(DS.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typography.metadata)
                    .foregroundStyle(Color.statusBad)
            }

            HStack(spacing: DS.Space.sm) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try onSave(name, url)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || (profile.type == .remote && url.isEmpty))
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 420)
    }
}
