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
    
    var body: some View {
        ScrollView {
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
    let onDelete: () -> Void
    
    @State private var isUpdating = false
    @EnvironmentObject var profileService: ProfileService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(profile.name)
                        .font(.headline)
                    if let url = profile.url {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let lastUpdated = profile.lastUpdated {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.footnote)
                            Text(lastUpdated, style: .relative)
                                .font(.footnote)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            
            // Subscription Info Section
            if let sub = profile.subscriptionInfo {
                VStack(alignment: .leading, spacing: 6) {
                    // Traffic Usage
                    HStack {
                        Text("Traffic")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatBytes(sub.used)) / \(formatBytes(sub.total))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: Double(sub.used), total: Double(sub.total))
                        .progressViewStyle(.linear)
                        .tint(usageColor(used: sub.used, total: sub.total))
                        .scaleEffect(x: 1, y: 0.5, anchor: .center)
                    
                    // Expiry Date
                    if let expire = sub.expire {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text("Expires: \(expire, style: .date)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            HStack(spacing: 8) {
                Button("Select") {
                    onSelect()
                }
                .buttonStyle(.bordered)
                .disabled(isActive)
                
                // Update button for remote profiles
                if case .remote = profile.type {
                    Button {
                        Task {
                            isUpdating = true
                            try? await profileService.updateProfile(id: profile.id)
                            isUpdating = false
                        }
                    } label: {
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isUpdating)
                    .help("Update subscription")
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(isActive ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
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
