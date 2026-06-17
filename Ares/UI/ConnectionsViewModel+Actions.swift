import Foundation
import AppKit

extension ConnectionsViewModel {
    func killProcess(for session: AppSession) {
        // Find PID from active connections if possible, or use `pkill` by process name/path?
        // Since we aggregated by bundle path, we might kill all instances.

        // Strategy: Iterate all active connections of this session, find PIDs (we don't store PID in public Contract yet but metadata might have it implicitly or we use path)
        // Actually, TrafficAudit logic uses path.
        // We will attempt to kill by path matching active running applications.

        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.path == session.id || $0.executableURL?.path == session.id
        }) {
            app.forceTerminate()
        } else {
            // Fallback: Shell kill
             let task = Process()
             task.launchPath = "/usr/bin/pkill"
             task.arguments = ["-f", session.id]
             try? task.run()
        }
    }

    func exportData(to url: URL) async {
        var csv = "Time,ID,Type,Host,RemoteIP,RemotePort,Upload,Download,Duration,Rule,Chains\n"
        for conn in self.connections {
            let line = [
                conn.start.ISO8601Format(),
                conn.id,
                conn.typeString,
                conn.metadata.host,
                conn.metadata.destinationIP,
                conn.metadata.destinationPort,
                String(conn.upload),
                String(conn.download),
                String(conn.duration),
                conn.rule,
                conn.chains.joined(separator: " -> ")
            ].map { "\"\($0)\"" }.joined(separator: ",")
            csv += line + "\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
