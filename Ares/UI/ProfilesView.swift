import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @EnvironmentObject var profileService: ProfileService
    @State private var showingAddSheet = false
    @State private var showingFileImporter = false
    @State private var newProfileName = ""
    @State private var newProfileURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingProfile: Profile?
    @State private var editingRawProfile: Profile?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                // "Add Profile" Card
                Menu {
                    Button("Remote Subscription") {
                        showingAddSheet = true
                    }
                    Button("Local File") {
                        showingFileImporter = true
                    }
                } label: {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)
                        Text("Add Profile")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundStyle(.blue.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
                
                // Existing Profiles
                ForEach(profileService.profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        isActive: profileService.activeProfileID == profile.id,
                        onSelect: {
                            profileService.setActiveProfile(id: profile.id)
                        },
                        onEdit: {
                            editingProfile = profile
                        },
                        onEditRaw: {
                            editingRawProfile = profile
                        },
                        onDelete: {
                            profileService.deleteProfile(id: profile.id)
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Profiles")
        .sheet(isPresented: $showingAddSheet) {
            AddProfileSheet(
                name: $newProfileName,
                url: $newProfileURL,
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                onAdd: {
                    Task {
                        await addProfile()
                    }
                },
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
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else { return }
            
            // Get file name without extension as default name
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

struct ProfileCard: View {
    let profile: Profile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onEditRaw: () -> Void
    let onDelete: () -> Void
    
    @State private var isUpdating = false
    @EnvironmentObject var profileService: ProfileService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Profile Avatar/Logo Representative
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? Color.blue : Color.primary.opacity(0.05))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: profile.type == .remote ? "cloud.fill" : "doc.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isActive ? .white : .blue)
                }
                .shadow(color: isActive ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if let urlString = profile.url?.absoluteString {
                        Text(urlString)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Local Configuration")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
            }
            
            // Subscription Info Section
            if let sub = profile.subscriptionInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Traffic Usage", systemImage: "chart.pie.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatBytes(sub.used)) / \(formatBytes(sub.total))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [usageColor(used: sub.used, total: sub.total), usageColor(used: sub.used, total: sub.total).opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: max(0, min(geo.size.width, geo.size.width * Double(sub.used) / Double(sub.total))), height: 6)
                                .shadow(color: usageColor(used: sub.used, total: sub.total).opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                    }
                    .frame(height: 6)
                    
                    // Expiry & Last Update
                    HStack {
                        if let expire = sub.expire {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(expire, style: .date)
                            }
                        }
                        
                        Spacer()
                        
                        if let lastUpdated = profile.lastUpdated {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text(lastUpdated, style: .relative)
                                Text("ago")
                            }
                        }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(10)
            }
            
            Spacer(minLength: 0)
            
            // Actions
            HStack(spacing: 10) {
                Button(action: onSelect) {
                    Text(isActive ? "Selected" : "Select")
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .blue : .secondary)
                .disabled(isActive)
                
                HStack(spacing: 4) {
                    if profile.type == .remote {
                        ActionButton(icon: "arrow.clockwise", tooltip: "Update") {
                            Task {
                                isUpdating = true
                                try? await profileService.updateProfile(id: profile.id)
                                isUpdating = false
                            }
                        }
                        .disabled(isUpdating)
                    }
                    
                    ActionButton(icon: "pencil", tooltip: "Rename") { onEdit() }
                    ActionButton(icon: "curlybraces", tooltip: "Code") { onEditRaw() }
                    
                    Spacer()
                    
                    ActionButton(icon: "trash", tooltip: "Delete", color: .red) { onDelete() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(isActive ? 0.08 : 0.04), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? Color.blue.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: isActive ? 2 : 1)
        )
    }
    
    // Helper to format bytes
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    // Helper to determine progress bar color
    private func usageColor(used: Int64, total: Int64) -> Color {
        let ratio = total > 0 ? Double(used) / Double(total) : 0
        if ratio > 0.9 { return .red }
        if ratio > 0.7 { return .orange }
        return .blue
    }
}

struct ActionButton: View {
    let icon: String
    let tooltip: String
    var color: Color = .primary
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHovered ? color : color.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(isHovered ? color.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

struct AddProfileSheet: View {
    @Binding var name: String
    @Binding var url: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onAdd: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Remote Profile")
                .font(.headline)
                .fontWeight(.bold)
            
            TextField("Profile Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
            
            TextField("Subscription URL", text: $url)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Add") {
                    onAdd()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || name.isEmpty || url.isEmpty)
            }
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(30)
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
        VStack(spacing: 20) {
            Text("Edit Profile")
                .font(.headline)
                .fontWeight(.bold)
            
            TextField("Profile Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
            
            if case .remote = profile.type {
                TextField("Subscription URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)
            } else {
                Text("Local profile URL cannot be edited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
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
                .disabled(name.isEmpty || (profile.type == .remote && url.isEmpty))
            }
        }
        .padding(30)
    }
}
