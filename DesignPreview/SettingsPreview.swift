import SwiftUI

/// In-memory Settings fixture. Shared tabs, typography, row style and card surfaces.
struct SettingsPreview: View {
    @State private var tab = 0
    @State private var toggles: Set<String> = ["Open in menu bar only", "Automatically check for updates", "Auto Route", "Auto Detect Interface"]
    @State private var fields: [String: String] = ["HTTP Port": "7892", "SOCKS Port": "7891", "Mixed Port": "7890", "DNS Servers": "223.5.5.5, 119.29.29.29", "MTU (bytes)": "1400", "Keep-Alive Interval (s)": "15", "UDP Timeout (s)": "120", "Intercept Ports": "80, 443, 8080, 8443", "Bypass Domains": "localhost,127.*,10.*,172.16.0.0/12,192.168.*"]
    @State private var choice: [String: String] = [:]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                SettingsTabs(titles: ["General", "Network", "TUN", "MITM", "Rules"], selection: $tab)
                Spacer(minLength: DS.Space.sm)
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
    }
    private func binding(_ name: String) -> Binding<String> { Binding(get: { fields[name] ?? "" }, set: { fields[name] = $0 }) }
    private func toggle(_ name: String) -> some View {
        LabeledContent(name) {
            Toggle(name, isOn: Binding(get: { toggles.contains(name) }, set: { if $0 { toggles.insert(name) } else { toggles.remove(name) } })).labelsHidden().toggleStyle(.switch)
        }.labeledContentStyle(SettingsRowStyle())
    }
    private func field(_ name: String, width: CGFloat = 84) -> some View {
        LabeledContent(name) { TextField("", text: binding(name)).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).font(DS.Typography.body.monospaced()).frame(width: width) }.labeledContentStyle(SettingsRowStyle())
    }
    private func picker(_ name: String, values: [String]) -> some View {
        LabeledContent(name) { Picker(name, selection: Binding(get: { choice[name] ?? values[0] }, set: { choice[name] = $0 })) { ForEach(values, id: \.self) { Text($0) } }.labelsHidden().frame(width: 190) }.labeledContentStyle(SettingsRowStyle())
    }
    private func note(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func editor(_ name: String, height: CGFloat) -> some View {
        TextEditor(text: binding(name)).font(DS.Typography.secondary.monospaced()).scrollContentBackground(.hidden).padding(DS.Space.sm).frame(height: height).background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(Color.primary.opacity(0.045)))
    }
}
