import SwiftUI

struct ProfileEditorView: View {
    let profile: Profile
    @EnvironmentObject var profileService: ProfileService
    @Environment(\.dismiss) var dismiss
    
    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showingDiff = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Editor: \(profile.name)")
                        .font(.headline)
                    Text(profile.path?.lastPathComponent ?? "Untitled.yaml")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { showingDiff.toggle() }) {
                        Label(showingDiff ? "Editor" : "Diff", systemImage: showingDiff ? "pencil" : "arrow.triangle.merge")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Button {
                        saveContent()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                        } else {
                            Text("Save & Apply")
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || isSaving)
                }
            }
            .padding()
            .background(DS.canvas)
            
            Divider()
            
            // Editor
            ZStack {
                if isLoading {
                    ProgressView("Loading configuration...")
                } else if showingDiff {
                    ProfileDiffView(original: originalContent, current: content)
                } else {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .padding(8)
                }
                
                if let error = errorMessage {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.white)
                            Text(error)
                                .foregroundColor(.white)
                                .font(.footnote)
                            Spacer()
                            Button {
                                errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(8)
                        .padding()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        Task {
            do {
                let fetched = try await profileService.readProfileContent(id: profile.id)
                content = fetched
                originalContent = fetched
                isLoading = false
            } catch {
                errorMessage = "Failed to load profile: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func saveContent() {
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                try await profileService.updateProfileContent(id: profile.id, content: content)
                isSaving = false
                dismiss()
            } catch {
                errorMessage = "Failed to save profile: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

struct ProfileDiffView: View {
    let original: String
    let current: String
    
    struct DiffLine: Identifiable {
        let id = UUID()
        let text: String
        let type: DiffType
    }
    
    enum DiffType {
        case added, removed, unchanged
    }
    
    var diffLines: [DiffLine] {
        let oldLines = original.components(separatedBy: .newlines)
        let newLines = current.components(separatedBy: .newlines)
        
        // Very basic diff implementation: only handles simple changes
        // For a real app, you'd use a better algorithm, but this shows the idea
        var result: [DiffLine] = []
        
        // Simple line-by-line comparison
        let maxLines = max(oldLines.count, newLines.count)
        for i in 0..<maxLines {
            if i < oldLines.count && i < newLines.count {
                if oldLines[i] == newLines[i] {
                    result.append(DiffLine(text: oldLines[i], type: .unchanged))
                } else {
                    result.append(DiffLine(text: oldLines[i], type: .removed))
                    result.append(DiffLine(text: newLines[i], type: .added))
                }
            } else if i < oldLines.count {
                result.append(DiffLine(text: oldLines[i], type: .removed))
            } else if i < newLines.count {
                result.append(DiffLine(text: newLines[i], type: .added))
            }
        }
        
        return result
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(diffLines) { line in
                    HStack(spacing: 8) {
                        Text(line.type == .added ? "+" : (line.type == .removed ? "-" : " "))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 20)
                        
                        Text(line.text)
                            .font(.system(.body, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(backgroundColor(for: line.type))
                    .foregroundStyle(foregroundColor(for: line.type))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private func backgroundColor(for type: DiffType) -> Color {
        switch type {
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .unchanged: return Color.clear
        }
    }
    
    private func foregroundColor(for type: DiffType) -> Color {
        switch type {
        case .added: return Color.green
        case .removed: return Color.red
        case .unchanged: return Color.primary.opacity(0.8)
        }
    }
}
