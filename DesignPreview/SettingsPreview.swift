import SwiftUI

/// In-memory Settings fixture. Shared tabs, typography, row style and card surfaces.
struct SettingsPreview: View {
    @State private var tab = CommandLine.arguments.contains("--settings-sources") ? 2 : 0
    @State private var showAudit = false
    @State private var localFields: Set<String> = ["MTU (bytes)"]
    @State private var toggles: Set<String> = ["Open in menu bar only", "Automatically check for updates", "Auto Route", "Auto Detect Interface"]
    @State private var fields: [String: String] = ["HTTP Port": "7892", "SOCKS Port": "7891", "Mixed Port": "7890", "DNS Servers": "223.5.5.5, 119.29.29.29", "MTU (bytes)": "1400", "Keep-Alive Interval (s)": "15", "UDP Timeout (s)": "120", "Intercept Ports": "80, 443, 8080, 8443", "Bypass Domains": "localhost,127.*,10.*,172.16.0.0/12,192.168.*"]
    @State private var choice: [String: String] = [:]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                SettingsTabs(titles: ["General", "Network", "TUN", "MITM", "Rules"], selection: $tab)
                Spacer(minLength: DS.Space.sm)
                Button { showAudit = true } label: { Image(systemName: "checkmark.magnifyingglass").font(.system(size: 14)) }
                    .buttonStyle(.borderless).help("Verify Running Configuration")
                    .accessibilityLabel("Verify Running Configuration")
                if tab != 0 {
                    Button("Discard") {}.buttonStyle(.borderless).disabled(true)
                    Button("Apply Changes") {}.buttonStyle(.bordered).disabled(true)
                }
            }.padding(DS.Space.md).background(DSSurfaceBackground())
                .padding(.horizontal, DS.Space.lg).padding(.top, DS.Space.pageTop).padding(.bottom, DS.Space.md)
                .frame(maxWidth: 820).frame(maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    switch tab {
                    case 0:
                        DSCard {
                            SettingsSectionTitle("Startup & Appearance", icon: "power")
                            toggle("Start with macOS")
                            toggle("Open in menu bar only")
                            picker("Theme", values: ["System", "Light", "Dark"])
                        }
                        DSCard { SettingsSectionTitle("Menu Bar", icon: "menubar.rectangle"); toggle("Show latency next to Ares") }
                        DSCard { SettingsSectionTitle("Logging", icon: "doc.text.magnifyingglass"); picker("Log Level", values: ["Info", "Silent", "Error", "Warning", "Debug"]) }
                        DSCard {
                            SettingsSectionTitle("Software Update", icon: "arrow.down.circle")
                            toggle("Automatically check for updates")
                            LabeledContent("Ares 1.0.6") { Button("Check for Updates…") {} }.labeledContentStyle(SettingsRowStyle())
                        }
                        DSCard {
                            SettingsSectionTitle("Maintenance", icon: "wrench.and.screwdriver")
                            HStack { Button("Clear Cache") {}; Button("Reset to Defaults") {}; Spacer() }.buttonStyle(.bordered)
                            note("Clears downloaded response cache. Subscriptions and routing data are kept.")
                        }
                    case 1:
                        DSCard { SettingsSectionTitle("Local Ports", icon: "network"); field("HTTP Port"); field("SOCKS Port"); field("Mixed Port"); note("Apply Changes restarts the running core.") }
                        DSCard { SettingsSectionTitle("Traffic", icon: "globe"); toggle("Allow LAN"); toggle("IPv6 Support") }
                        DSCard { SettingsSectionTitle("DNS", icon: "server.rack"); field("DNS Servers", width: 300); note("Separate resolvers with commas.") }
                        DSCard { SettingsSectionTitle("TLS Fingerprint", icon: "hand.raised"); picker("Profile", values: ["Disabled (Default)", "Chrome (Recommended)", "Safari (iOS)", "Firefox", "Randomized"]); note("Default for supported nodes without their own TLS fingerprint.") }
                    case 2:
                        DSCard { toggle("Enable TUN Support"); note("Route device traffic through a virtual interface.") }
                        DSCard {
                            SettingsSectionTitle("Interface", icon: "bolt.shield")
                            picker("Network Stack", values: ["System", "Mixed (Recommended)", "gVisor"])
                            field("MTU (bytes)"); field("TUN Device", width: 120)
                            toggle("Auto Route"); toggle("Auto Detect Interface")
                            note("Administrator access is required to enable TUN. Apply Changes restarts the active core.")
                        }
                        DSCard { SettingsSectionTitle("Connection Tuning", icon: "timer"); field("Keep-Alive Interval (s)"); field("UDP Timeout (s)") }
                    case 3:
                        DSCard {
                            SettingsSectionTitle("Certificate Authority", icon: "lock.shield")
                            HStack { DSStatusPill(text: "Not trusted", status: .critical); Spacer(); Button("Trust Certificate…") {}; Button("Export") {} }.buttonStyle(.bordered)
                            note("Interception only works once the Ares root certificate is trusted in your login keychain.")
                        }
                        DSCard {
                            SettingsSectionTitle("Interception", icon: "arrow.left.arrow.right")
                            Text("Intercept Ports"); TextField("Ports", text: binding("Intercept Ports")).textFieldStyle(.roundedBorder)
                            note("TUN interception ports. Used when the host list is empty.")
                            Text("Host Whitelist"); TextField("Hosts (empty = all)", text: binding("Host Whitelist")).textFieldStyle(.roundedBorder)
                            note("Filters captured hosts in proxy mode; controls routing in TUN mode. Empty means all hosts.")
                        }
                    default:
                        DSCard { SettingsSectionTitle("Bypass Domains", icon: "arrow.uturn.left"); editor("Bypass Domains", height: 100); note("Comma-separated domains and IP ranges, e.g. localhost, 127.*, 192.168.*.") }
                        DSCard { SettingsSectionTitle("Custom Routing Rules", icon: "list.bullet.rectangle"); editor("Custom Routing Rules", height: 120); note("One rule per line, e.g. DOMAIN-SUFFIX,example.com,DIRECT. Takes priority over subscription rules. Use Apply Changes to activate.") }
                    }
                }.padding(.horizontal, DS.Space.lg).padding(.bottom, DS.Space.lg)
                    .frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
            }.scrollIndicators(.never)
        }.controlSize(.small).font(DS.Typography.body)
        .sheet(isPresented: $showAudit) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Running Configuration").font(.headline); Spacer(); Button("Check Again") {} }
                Text("Isolated preview · synthetic values only").font(.caption).foregroundStyle(.secondary)
                SettingsRuntimeTable(rows: [
                    .init(id: "mixed-port", saved: "7890", running: "7890", result: "Matches", differs: false),
                    .init(id: "mode", saved: "rule", running: "global", result: "Different", differs: true),
                    .init(id: "tun.mtu", saved: "1400", running: "—", result: "TUN inactive", differs: false),
                    .init(id: "dns", saved: "Configured", running: "—", result: "Not exposed", differs: false)
                ])
                HStack { Spacer(); Button("Done") { showAudit = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 720, height: 480)
        }
    }
    private func binding(_ name: String) -> Binding<String> { Binding(get: { fields[name] ?? "" }, set: { fields[name] = $0 }) }
    private func toggle(_ name: String) -> some View {
        LabeledContent(name) {
            Toggle(name, isOn: Binding(get: { toggles.contains(name) }, set: { if $0 { toggles.insert(name) } else { toggles.remove(name) } })).labelsHidden().toggleStyle(.switch)
        }.labeledContentStyle(SettingsRowStyle())
    }
    private func field(_ name: String, width: CGFloat = 84) -> some View {
        HStack(spacing: 16) {
            sourceLabel(name).font(.system(size: 13))
            Spacer(minLength: 16)
            if inheritedFields.contains(name) && !localFields.contains(name) {
                Text(fields[name] ?? "Core default").font(DS.Typography.secondary.monospaced())
            } else {
                TextField("", text: binding(name)).textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing).font(DS.Typography.body.monospaced()).frame(width: width)
            }
        }.frame(minHeight: 28).frame(maxWidth: .infinity)
    }
    private let inheritedFields = ["DNS Servers", "MTU (bytes)", "TUN Device", "Keep-Alive Interval (s)", "UDP Timeout (s)"]
    private func picker(_ name: String, values: [String]) -> some View {
        LabeledContent(name) { Picker(name, selection: Binding(get: { choice[name] ?? values[0] }, set: { choice[name] = $0 })) { ForEach(values, id: \.self) { Text($0) } }.labelsHidden().frame(width: 190) }.labeledContentStyle(SettingsRowStyle())
    }
    @ViewBuilder private func sourceLabel(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
            if inheritedFields.contains(name) {
                SettingsSourceControl(source: localFields.contains(name) ? "Local override" : (name == "TUN Device" ? "Core default" : "Subscription"),
                    isLocal: localFields.contains(name), pending: false) {
                        if localFields.contains(name) { localFields.remove(name) } else { localFields.insert(name) }
                    }
            }
        }
    }
    private func note(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func editor(_ name: String, height: CGFloat) -> some View {
        TextEditor(text: binding(name)).font(DS.Typography.secondary.monospaced()).scrollContentBackground(.hidden).padding(DS.Space.sm).frame(height: height).background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(Color.primary.opacity(0.045)))
    }
}
