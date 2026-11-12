import Foundation
import AppKit
import Darwin

actor ConfigDirectoryPreparation {
    static let shared = ConfigDirectoryPreparation()

    func prepare(_ directory: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let config = directory.appendingPathComponent("config.yaml")
        if (try? config.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CocoaError(.fileWriteNoPermission)
        }
        do {
            try ConfigDirectoryAccess.verifyWritable(directory)
            return
        } catch {
            let attributes = try fm.attributesOfItem(atPath: directory.path)
            let configAttributes = try? fm.attributesOfItem(atPath: directory.appendingPathComponent("config.yaml").path)
            // Only legacy root-owned TUN directories need elevation. Other
            // failures (disk full, ACLs, read-only volumes) must remain errors.
            guard directory.lastPathComponent == "clash_root",
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0 ||
                  (configAttributes?[.ownerAccountID] as? NSNumber)?.uint32Value == 0 else { throw error }
        }

        let command = try ConfigDirectoryAccess.repairCommand(directory: directory, userID: getuid())
        let repaired = await MainActor.run {
            var error: NSDictionary?
            let script = NSAppleScript(source: "do shell script \"\(AppleScriptEscaper.stringLiteral(command))\" with administrator privileges")
            script?.executeAndReturnError(&error)
            return script != nil && error == nil
        }
        guard repaired else {
            throw NSError(domain: "ConfigDirectory", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Ares needs permission to repair its TUN configuration folder. Authorize the repair and try again."])
        }
        try ConfigDirectoryAccess.verifyWritable(directory)
    }
}
