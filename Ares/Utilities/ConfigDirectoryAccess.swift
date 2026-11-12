import Foundation

/// Repairs only the legacy TUN configuration directory, never the user's home,
/// other clients' directories, or links. Cached resource files remain untouched.
nonisolated enum ConfigDirectoryAccess {
    static func repairCommand(directory: URL, userID: UInt32) throws -> String {
        let directory = directory.standardizedFileURL
        guard userID > 0, directory.lastPathComponent == "clash_root",
              directory.deletingLastPathComponent().lastPathComponent == "Ares",
              try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              try directory.deletingLastPathComponent().resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let path = CoreProcessIdentity.shellQuote(directory.path)
        return """
        set -eu
        target=\(path)
        test -d "$target" && test ! -L "$target"
        test ! -L "$(/usr/bin/dirname "$target")"
        if test -e "$target/config.yaml" || test -L "$target/config.yaml"; then
            test -f "$target/config.yaml" && test ! -L "$target/config.yaml"
        fi
        /usr/sbin/chown -h \(userID) "$target"
        /bin/chmod u+rwx "$target"
        if test -e "$target/config.yaml" || test -L "$target/config.yaml"; then
            test -f "$target/config.yaml" && test ! -L "$target/config.yaml"
            /usr/sbin/chown -h \(userID) "$target/config.yaml"
            /bin/chmod u+rw "$target/config.yaml"
        fi
        """
    }

    static func verifyWritable(_ directory: URL) throws {
        let config = directory.appendingPathComponent("config.yaml")
        if FileManager.default.fileExists(atPath: config.path),
           !FileManager.default.isWritableFile(atPath: config.path) {
            throw CocoaError(.fileWriteNoPermission)
        }
        let probe = directory.appendingPathComponent(".ares-write-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: probe) }
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
    }
}
