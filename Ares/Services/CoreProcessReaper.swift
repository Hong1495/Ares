import Foundation
import Darwin
import AppKit

/// Reclaims current and legacy Ares children even after the original app has exited.
/// Never discovers signal targets by listener port or by a broad process-name match.
actor CoreProcessReaper {
    private let runner = ProcessManager()
    private let support: URL
    private let userID: UInt32

    init(support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ares"), userID: UInt32 = getuid()) {
        self.support = support
        self.userID = userID
    }

    func ownedProcesses() async throws -> [CoreProcessIdentity] {
        let result = try await runner.run(executable: "/bin/ps", arguments: ["-ww", "-axo", "pid=,uid=,lstart=,command="], timeout: 5)
        guard result.exitCode == 0 else { throw CocoaError(.fileReadUnknown) }
        return result.output.split(separator: "\n").compactMap { CoreProcessIdentity(line: String($0)) }
            .filter { $0.belongsToAres(support: support, userID: userID) }
    }

    func reap() async -> Bool {
        do {
            let owned = try await ownedProcesses()
            guard !owned.isEmpty else { return true }
            // End cores before sudo wrappers, letting sudo reap its own child normally.
            let ordered = owned.sorted { !$0.command.hasPrefix("/usr/bin/sudo ") && $1.command.hasPrefix("/usr/bin/sudo ") }
            for identity in ordered where identity.uid == userID {
                if try await ownedProcesses().contains(identity) { _ = Darwin.kill(identity.pid, SIGTERM) }
            }
            let roots = ordered.filter { $0.uid == 0 }
            if !roots.isEmpty {
                // Reuse the narrowly scoped helper installed during TUN authorization.
                // Older installations migrate once; never authorize an arbitrary kill command.
                let helper = CoreStopHelper.path(userID: userID)
                var result = try? await runner.run(executable: "/usr/bin/sudo", arguments: ["-n", helper], timeout: 30)
                if result?.exitCode != 0 {
                    guard await PrivilegeService.shared.installSudoers() else { return false }
                    result = try? await runner.run(executable: "/usr/bin/sudo", arguments: ["-n", helper], timeout: 30)
                }
                guard result?.exitCode == 0 else { return false }
            }
            // Bounded TERM grace period, then force only the same verified identities.
            for _ in 0..<30 {
                if try await ownedProcesses().isEmpty { return true }
                try await Task.sleep(for: .milliseconds(100))
            }
            let remaining = try await ownedProcesses()
            for identity in ordered where identity.uid == userID && remaining.contains(identity) {
                if try await ownedProcesses().contains(identity) { _ = Darwin.kill(identity.pid, SIGKILL) }
            }
            for _ in 0..<20 {
                if try await ownedProcesses().isEmpty { return true }
                try await Task.sleep(for: .milliseconds(100))
            }
            return false
        } catch { return false }
    }
}
