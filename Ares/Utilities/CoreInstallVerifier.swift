import CryptoKit
import Foundation

nonisolated enum CoreInstallVerifier {
    private static var manifestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func isManagedCoreUsable(binaryURL: URL, manifestURL: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.isExecutableFile(atPath: binaryURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? manifestDecoder.decode(CoreInstallManifest.self, from: data),
              let actualHash = try? sha256Hex(for: binaryURL),
              actualHash == manifest.sha256 else {
            return false
        }
        return true
    }

    static func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256Hex(for: data)
    }

    static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
