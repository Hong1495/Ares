import Foundation

/// Generates only synthetic files. Compile with ClashConfig/ClashPorts/DefaultsKeys.
@main struct GenerateFlowConfig {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        for tun in [false, true] {
            var config = ClashConfig()
            config.enableTun = tun
            // The test target has an IP address; avoid external geodata/DNS downloads.
            config.skipDNS = true
            config.tunDevice = "ares-test"
            let fixture = """
            proxies:
              - {name: Node A, type: http, server: 127.0.0.1, port: 18081}
              - {name: Node B, type: http, server: 127.0.0.1, port: 18082}
            proxy-groups:
              - name: Proxy
                type: select
                proxies: [Node A, Node B]
            rules:
              - MATCH,Proxy
            """
            try (config.toYAML() + "\n" + fixture + "\n").write(to: output.appendingPathComponent(tun ? "tun.yaml" : "normal.yaml"), atomically: true, encoding: .utf8)
        }
    }
}
