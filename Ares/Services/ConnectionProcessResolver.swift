import Foundation
import Darwin

/// Read-only local socket attribution when mihomo cannot populate process metadata.
/// Exact protocol + local endpoint + peer endpoint only; no port-only guesses.
actor ConnectionProcessResolver {
    static let shared = ConnectionProcessResolver()
    private let runner = ProcessManager()
    private var refresh: Task<[SocketOwner], Never>?

    func resolve(_ connections: [Connection]) async -> [Connection] {
        guard connections.contains(where: { ($0.metadata.processPath ?? "").isEmpty }) else { return connections }
        let task: Task<[SocketOwner], Never>
        if let refresh { task = refresh }
        else {
            task = Task {
                let result = try? await runner.run(executable: "/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-iUDP", "-FpcPfn"], timeout: 3)
                return SocketOwner.parse(result?.output ?? "")
            }
            refresh = task
        }
        let owners = await task.value
        refresh = nil
        var paths: [Int32: String] = [:]
        return connections.map { connection in
            var result = connection
            guard (result.metadata.processPath ?? "").isEmpty,
                  let owner = SocketOwner.match(result.metadata, in: owners) else { return result }
            if paths[owner.pid] == nil {
                var buffer = [CChar](repeating: 0, count: 4096)
                let count = proc_pidpath(owner.pid, &buffer, UInt32(buffer.count))
                paths[owner.pid] = count > 0 ? String(cString: buffer) : ""
            }
            result.metadata.processPath = paths[owner.pid]
            result.metadata.process = owner.process
            return result
        }
    }
}
