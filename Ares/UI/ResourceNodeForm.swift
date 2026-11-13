import SwiftUI
import SubscriptionKit
import Yams

/// Patches owned fields into the original mapping, keeping advanced fields intact.
struct ResourceNodeForm: View {
    @Binding var source: String
    let provider: Bool
    @State private var type = "vless"
    @State private var server = ""
    @State private var port = "443"
    @State private var credential = ""
    @State private var cipher = ["aes", "128", "gcm"].joined(separator: "-")
    @State private var tls = true
    @State private var sni = ""
    @State private var url = ""
    @State private var interval = "3600"
    @State private var ready = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if provider {
                field("URL", text: $url)
                field("Interval (s)", text: $interval)
            } else {
                HStack { Text("Protocol"); Text(type.uppercased()).foregroundStyle(.secondary) }
                field("Server", text: $server)
                field("Port", text: $port)
                if ["vless", "vmess"].contains(type) { field("UUID", text: $credential) }
                else if ["trojan", "ss"].contains(type) { LabeledContent("Password") { SecureField("Password", text: $credential).labelsHidden() } }
                if type == "ss" { field("Cipher", text: $cipher) }
                if type == "vless" || type == "vmess" { Toggle("TLS", isOn: $tls) }
                if ["vless", "vmess", "trojan"].contains(type) { field("SNI", text: $sni) }
            }
            if let error { Text(error).font(DS.Typography.metadata).foregroundStyle(Color.statusBad) }
        }.textFieldStyle(.roundedBorder).controlSize(.small)
        .onAppear { read() }
        .onChange(of: server) { _, _ in patch() }.onChange(of: port) { _, _ in patch() }
        .onChange(of: credential) { _, _ in patch() }.onChange(of: cipher) { _, _ in patch() }
        .onChange(of: tls) { _, _ in patch() }.onChange(of: sni) { _, _ in patch() }
        .onChange(of: url) { _, _ in patch() }.onChange(of: interval) { _, _ in patch() }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(DS.Typography.metadata).foregroundStyle(.secondary); TextField(title, text: text).labelsHidden() }
    }
    private func read() {
        do {
            let node = try ManagedResources.document(source)
            type = node["type"]?.string ?? "vless"; server = node["server"]?.string ?? ""
            port = node["port"]?.int.map(String.init) ?? "443"
            credential = node[["vless", "vmess"].contains(type) ? "uuid" : "password"]?.string ?? ""
            cipher = node["cipher"]?.string ?? ["aes", "128", "gcm"].joined(separator: "-"); tls = node["tls"]?.bool ?? (type == "trojan")
            sni = node[type == "trojan" ? "sni" : "servername"]?.string ?? ""
            url = node["url"]?.string ?? ""; interval = node["interval"]?.int.map(String.init) ?? "3600"
            ready = true
        } catch { self.error = "Use Source to repair this YAML mapping." }
    }
    private func patch() {
        guard ready else { return }
        do {
            var node = try ManagedResources.document(source)
            if provider {
                node["url"] = Node(url, Tag(.str)); node["interval"] = Node(interval, Int(interval) == nil ? Tag(.str) : Tag(.int))
            } else {
                node["server"] = Node(server, Tag(.str)); node["port"] = Node(port, Int(port) == nil ? Tag(.str) : Tag(.int))
                if ["vless", "vmess", "trojan", "ss"].contains(type) { node[["vless", "vmess"].contains(type) ? "uuid" : "password"] = Node(credential, Tag(.str)) }
                if type == "ss" { node["cipher"] = Node(cipher, Tag(.str)) }
                if type == "vless" || type == "vmess" { node["tls"] = Node(tls ? "true" : "false", Tag(.bool)) }
                if ["vless", "vmess", "trojan"].contains(type) { node[type == "trojan" ? "sni" : "servername"] = Node(sni, Tag(.str)) }
            }
            source = try ManagedResources.yaml(node); error = nil
        } catch { self.error = "Could not update the resource fields." }
    }
}
