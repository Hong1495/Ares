import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selection },
                set: { newValue in
                    DispatchQueue.main.async {
                        if let val = newValue {
                            appState.selection = val
                        }
                    }
                }
            )) {
                // 1. Dashboard
                NavigationLink(value: AppState.NavigationItem.dashboard) {
                    Label {
                        Text("Dashboard")
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 2. Activity (Connections)
                NavigationLink(value: AppState.NavigationItem.connections) {
                    Label {
                        Text("Activity")
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 3. Policies (Combined Proxies & Rules)
                NavigationLink(value: AppState.NavigationItem.policies) {
                    Label {
                        Text("Policies")
                    } icon: {
                        Image(systemName: "hand.tap")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 4. Analysis
                NavigationLink(value: AppState.NavigationItem.analysis) {
                    Label {
                        Text("Analysis")
                    } icon: {
                        Image(systemName: "chart.bar")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }

                // 5. Logs
                NavigationLink(value: AppState.NavigationItem.logs) {
                    Label {
                        Text("Logs")
                    } icon: {
                        Image(systemName: "terminal")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
                
                // 6. Settings
                NavigationLink(value: AppState.NavigationItem.settings) {
                    Label {
                        Text("Settings")
                    } icon: {
                        Image(systemName: "gear")
                            .imageScale(.medium)
                            .fontWeight(.light)
                            .frame(width: 20)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                SidebarFooterView()
            }
            .navigationTitle(appState.selection.displayName)
        } detail: {
            switch appState.selection {
            case .dashboard:
                DashboardView()
            case .policies:
                PoliciesView()
            case .connections:
                ConnectionsView()
            case .analysis:
                AnalysisView()
            case .logs:
                LogsView()
            case .settings:
                SettingsView()
            }
        }
    }
}

struct SidebarFooterView: View {
    @EnvironmentObject var profileService: ProfileService
    @State private var showingProfilesSheet = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
                .opacity(0.5)
            
            Menu {
                Section("Switch Profile") {
                    ForEach(profileService.profiles) { profile in
                        Button {
                            withAnimation {
                                profileService.setActiveProfile(id: profile.id)
                            }
                        } label: {
                            HStack {
                                Text(profile.name)
                                if profileService.activeProfileID == profile.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    showingProfilesSheet = true
                } label: {
                    Label("Manage Profiles...", systemImage: "rectangle.stack")
                }
            } label: {
                HStack(spacing: 12) {
                    // Avatar/Icon (Minimalist Style)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 30, height: 30)
                        
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profileService.activeProfile?.name ?? "No Profile")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text("Active Profile")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? Color.primary.opacity(0.1) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
        .sheet(isPresented: $showingProfilesSheet) {
            NavigationStack {
                ProfilesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingProfilesSheet = false
                            }
                        }
                    }
            }
            .frame(minWidth: 700, minHeight: 500)
        }
    }
}
