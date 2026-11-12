import CryptoKit
import Foundation

nonisolated struct CoreVersionInfo: Equatable {
    let displayVersion: String
    let rawOutput: String
    let binaryPath: String

    static let unknown = CoreVersionInfo(displayVersion: "Unknown", rawOutput: "", binaryPath: "")
}

nonisolated struct CoreReleaseInfo: Equatable {
    let version: String
    let pageURL: URL
    let assetURL: URL?
    let assetName: String?
}

nonisolated struct CoreInstallManifest: Codable, Equatable {
    let version: String
    let assetName: String
    let assetURL: String
    let sha256: String
    let installedAt: Date
}

actor CoreManager {
    static let shared = CoreManager()

    private let bundledResourceName = "clash-meta"
    private var cachedVersion: CoreVersionInfo?
    private let fileManager = FileManager.default

    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ares")
    }

    private var managedCoreDir: URL {
        appSupportDir.appendingPathComponent("Core")
    }

    private var managedBinaryURL: URL {
        managedCoreDir.appendingPathComponent("mihomo")
    }

    private var manifestURL: URL {
        managedCoreDir.appendingPathComponent("manifest.json")
    }

    private var previousManifestURL: URL {
        managedCoreDir.appendingPathComponent("manifest.previous.json")
    }

    private init() {}

    func bundledBinaryPath() -> String? {
        Bundle.main.path(forResource: bundledResourceName, ofType: nil)
    }

    func activeBinaryPath() -> String {
        if CoreInstallVerifier.isManagedCoreUsable(binaryURL: managedBinaryURL, manifestURL: manifestURL, fileManager: fileManager) {
            return managedBinaryURL.path
        }
        return bundledBinaryPath() ?? "/usr/local/bin/clash-meta"
    }

    func versionInfo(forceRefresh: Bool = false) async -> CoreVersionInfo {
        if !forceRefresh, let cachedVersion {
            return cachedVersion
        }

        let path = activeBinaryPath()
        guard FileManager.default.fileExists(atPath: path) else {
            let info = CoreVersionInfo(displayVersion: "Missing", rawOutput: "", binaryPath: path)
            cachedVersion = info
            return info
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-v"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let raw = [output, error].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let display = CoreReleaseSelector.parseDisplayVersion(from: raw)
            let info = CoreVersionInfo(displayVersion: display, rawOutput: raw, binaryPath: path)
            cachedVersion = info
            return info
        } catch {
            let info = CoreVersionInfo(displayVersion: "Unavailable", rawOutput: "\(error)", binaryPath: path)
            cachedVersion = info
            return info
        }
    }

    func validateConfig(configDir: URL, configFile: URL? = nil) async -> Bool {
        (try? await validateConfigStrict(configDir: configDir, configFile: configFile)) == true
    }

    func validateConfigStrict(configDir: URL, configFile: URL? = nil) async throws -> Bool {
        let path = activeBinaryPath()
        guard FileManager.default.fileExists(atPath: path) else { throw CoreManagerError.binaryNotExecutable }
        var arguments = ["-t", "-d", configDir.path]
        if let configFile { arguments += ["-f", configFile.path] }
        let result = try await ProcessManager().run(executable: path, arguments: arguments, timeout: 15)
        if result.exitCode == 0 { return true }
        if ConfigurationValidationFailure.isResourceFailure(result.output + result.error) {
            throw ConfigurationValidationFailure.resourcesUnavailable
        }
        return false
    }

    func latestRelease() async -> CoreReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String,
                  let pageURL = URL(string: htmlURL) else {
                return nil
            }
            let asset = Self.selectDarwinARM64Asset(from: json["assets"] as? [[String: Any]])
            return CoreReleaseInfo(version: tagName, pageURL: pageURL, assetURL: asset?.url, assetName: asset?.name)
        } catch {
            return nil
        }
    }

    func installLatestRelease() async throws -> CoreVersionInfo {
        guard let release = await latestRelease() else {
            throw CoreManagerError.releaseUnavailable
        }
        guard let assetURL = release.assetURL, let assetName = release.assetName else {
            throw CoreManagerError.assetUnavailable
        }

        try fileManager.createDirectory(at: managedCoreDir, withIntermediateDirectories: true)

        let archiveURL = managedCoreDir.appendingPathComponent(assetName)
        let tempURL = managedCoreDir.appendingPathComponent("mihomo.download")
        let backupURL = managedCoreDir.appendingPathComponent("mihomo.previous")

        let (downloadedURL, response) = try await URLSession.shared.download(from: assetURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CoreManagerError.downloadFailed
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)

        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }

        try extractCore(from: archiveURL, to: tempURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        let installedVersion = try installedVersion(at: tempURL)
        guard installedVersion == release.version else {
            throw CoreManagerError.versionMismatch(expected: release.version, actual: installedVersion)
        }
        let sha256 = try CoreInstallVerifier.sha256Hex(for: tempURL)
        let manifest = CoreInstallManifest(
            version: installedVersion,
            assetName: assetName,
            assetURL: assetURL.absoluteString,
            sha256: sha256,
            installedAt: Date()
        )

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        if fileManager.fileExists(atPath: previousManifestURL.path) {
            try fileManager.removeItem(at: previousManifestURL)
        }
        if fileManager.fileExists(atPath: managedBinaryURL.path) {
            try fileManager.moveItem(at: managedBinaryURL, to: backupURL)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.moveItem(at: manifestURL, to: previousManifestURL)
        }
        try fileManager.moveItem(at: tempURL, to: managedBinaryURL)
        try writeManifest(manifest, to: manifestURL)

        cachedVersion = nil
        return await versionInfo(forceRefresh: true)
    }

    func rollbackManagedCore() async throws -> CoreVersionInfo {
        let backupURL = managedCoreDir.appendingPathComponent("mihomo.previous")

        if fileManager.fileExists(atPath: backupURL.path) {
            if fileManager.fileExists(atPath: managedBinaryURL.path) {
                try fileManager.removeItem(at: managedBinaryURL)
            }
            try fileManager.moveItem(at: backupURL, to: managedBinaryURL)
            if fileManager.fileExists(atPath: manifestURL.path) {
                try fileManager.removeItem(at: manifestURL)
            }
            if fileManager.fileExists(atPath: previousManifestURL.path) {
                try fileManager.moveItem(at: previousManifestURL, to: manifestURL)
            }
        } else if fileManager.fileExists(atPath: managedBinaryURL.path) {
            try fileManager.removeItem(at: managedBinaryURL)
            if fileManager.fileExists(atPath: manifestURL.path) {
                try fileManager.removeItem(at: manifestURL)
            }
        }

        cachedVersion = nil
        return await versionInfo(forceRefresh: true)
    }

    nonisolated func isUpdateAvailable(current: String, latest: String) -> Bool {
        CoreReleaseSelector.isUpdateAvailable(current: current, latest: latest)
    }

    private static func selectDarwinARM64Asset(from assets: [[String: Any]]?) -> (name: String, url: URL)? {
        guard let assets else { return nil }
        let releaseAssets = assets.compactMap { asset -> (name: String, url: URL)? in
            guard let name = asset["name"] as? String,
                  let browserDownloadURL = asset["browser_download_url"] as? String,
                  let url = URL(string: browserDownloadURL) else {
                return nil
            }
            return (name, url)
        }
        return CoreReleaseSelector.selectDarwinARM64Asset(from: releaseAssets)
    }

    private func extractCore(from archiveURL: URL, to outputURL: URL) throws {
        let name = archiveURL.lastPathComponent.lowercased()
        if name.hasSuffix(".gz") {
            try runTool("/usr/bin/gunzip", arguments: ["-c", archiveURL.path], outputURL: outputURL)
        } else if name.hasSuffix(".zip") {
            let tempDir = managedCoreDir.appendingPathComponent("extract-\(UUID().uuidString)")
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }
            let entries = try zipArchiveEntries(archiveURL)
            guard CoreArchiveExtractor.zipEntriesAreSafe(entries) else {
                throw CoreManagerError.extractFailed
            }
            try runTool("/usr/bin/unzip", arguments: ["-o", archiveURL.path, "-d", tempDir.path], outputURL: nil)
            guard let extracted = try CoreArchiveExtractor.findCoreBinary(in: tempDir, fileManager: fileManager) else {
                throw CoreManagerError.extractFailed
            }
            try fileManager.moveItem(at: extracted, to: outputURL)
        } else {
            throw CoreManagerError.assetUnavailable
        }
    }

    private func runTool(_ path: String, arguments: [String], outputURL: URL?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = Pipe()

        if let outputURL {
            fileManager.createFile(atPath: outputURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: outputURL)
            process.standardOutput = handle
            try process.run()
            process.waitUntilExit()
            try handle.close()
        } else {
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
        }

        guard process.terminationStatus == 0 else {
            throw CoreManagerError.extractFailed
        }
    }

    private func zipArchiveEntries(_ archiveURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archiveURL.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CoreManagerError.extractFailed
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func installedVersion(at binaryURL: URL) throws -> String {
        guard fileManager.isExecutableFile(atPath: binaryURL.path) else {
            throw CoreManagerError.binaryNotExecutable
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["-v"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CoreManagerError.binaryNotExecutable
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let raw = [output, error].joined(separator: "\n")
        return CoreReleaseSelector.parseDisplayVersion(from: raw)
    }

    private func writeManifest(_ manifest: CoreInstallManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}

enum CoreManagerError: LocalizedError {
    case releaseUnavailable
    case assetUnavailable
    case downloadFailed
    case extractFailed
    case binaryNotExecutable
    case versionMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .releaseUnavailable: return "Latest release unavailable"
        case .assetUnavailable: return "Darwin arm64 asset unavailable"
        case .downloadFailed: return "Core download failed"
        case .extractFailed: return "Core extract failed"
        case .binaryNotExecutable: return "Downloaded core is not executable"
        case .versionMismatch(let expected, let actual): return "Core version mismatch: expected \(expected), got \(actual)"
        }
    }
}
