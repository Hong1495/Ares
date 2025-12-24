import Foundation
import Security
import Combine

/// Manages certificates for MITM interception
final class CertificateManager: ObservableObject {
    static let shared = CertificateManager()
    
    private let fileManager = FileManager.default
    private var certsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let aresDir = appSupport.appendingPathComponent("Ares")
        let dir = aresDir.appendingPathComponent("Certs")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var caCertPath: URL { certsDirectory.appendingPathComponent("ca.crt") }
    public var rootCAPath: URL { caCertPath } // Expose for internal pinning
    private var caKeyPath: URL { certsDirectory.appendingPathComponent("ca.key") }
    
    @Published var isRootCAInstalled = false
    
    private var openSSLConfigPath: URL { certsDirectory.appendingPathComponent("openssl.cnf") }

    // Cache for SecIdentity to prevent Keychain thrashing
    private let identityCache = NSCache<NSString, AnyObject>()

    private init() {
        Task {
            await MainActor.run { self.checkRootCA() }
            await self.cleanupLegacyCerts()
        }
    }

    @MainActor
    func checkRootCA() {
        isRootCAInstalled = fileManager.fileExists(atPath: caCertPath.path) &&
                            fileManager.fileExists(atPath: caKeyPath.path)
    }

    /// Cleans up old host certificates to force regeneration (fixes SAN issues)
    private func cleanupLegacyCerts() async {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: certsDirectory, includingPropertiesForKeys: nil) else { return }
        
        for file in files {
            let filename = file.lastPathComponent
            // Keep CA files and config
            if filename.hasPrefix("ca.") || filename == "openssl.cnf" { continue }
            try? fileManager.removeItem(at: file)
        }
        print("[CertificateManager] 🧹 Cleaned up legacy host certificates")
    }

    /// Generates a new Root CA with proper extensions
    func generateRootCA() async throws {
        let caKey = caKeyPath.path
        let caCert = caCertPath.path
        let config = openSSLConfigPath.path
        
        // 0. Create OpenSSL Config
        let configContent = """
        [ req ]
        default_bits       = 2048
        distinguished_name = req_distinguished_name
        x509_extensions    = v3_ca
        prompt             = no
        
        [ req_distinguished_name ]
        CN = Ares MITM Proxy CA [\(UUID().uuidString.prefix(8))]
        O  = Ares
        C  = US
        
        [ v3_ca ]
        subjectKeyIdentifier = hash
        authorityKeyIdentifier = keyid:always,issuer
        basicConstraints = critical,CA:true
        keyUsage = critical, digitalSignature, cRLSign, keyCertSign
        """
        
        try configContent.write(to: openSSLConfigPath, atomically: true, encoding: .utf8)
        
        // 1. Generate CA Private Key
        try await runOpenSSL(["genrsa", "-out", caKey, "2048"])
        
        // 2. Generate CA Certificate using Config
        try await runOpenSSL([
            "req", "-new", "-x509", "-days", "3650",
            "-key", caKey,
            "-out", caCert,
            "-config", config
        ])
        
        await MainActor.run { checkRootCA() }
    }
    
    // In-flight tasks to prevent duplicate generation for the same host
    private var inflightIdentities: [String: Task<SecIdentity, Error>] = [:]

    /// Gets (or generates) a SecIdentity for a specific host
    func getIdentity(for host: String) async throws -> SecIdentity {
        // 1. Check Cache
        if let cached = identityCache.object(forKey: host as NSString) {
            return (cached as! SecIdentity)
        }
        
        // 2. Check In-flight Tasks
        if let task = inflightIdentities[host] {
            return try await task.value
        }
        
        // 3. Create new task
        let task = Task { () -> SecIdentity in
            defer { 
                 DispatchQueue.main.async { [weak self] in 
                     self?.inflightIdentities.removeValue(forKey: host) 
                 }
            }
            return try await self._getIdentity(for: host)
        }
        
        inflightIdentities[host] = task
        return try await task.value
    }

    private func _getIdentity(for host: String) async throws -> SecIdentity {
        let hostClean = host.replacingOccurrences(of: "*", with: "wildcard")
        let hostKey = certsDirectory.appendingPathComponent("\(hostClean).key").path
        let hostCsr = certsDirectory.appendingPathComponent("\(hostClean).csr").path
        let hostCert = certsDirectory.appendingPathComponent("\(hostClean).crt").path
        let hostP12 = certsDirectory.appendingPathComponent("\(hostClean).p12").path
        let keyLabel = "Ares-Key-\(host)"
        
        // If P12 exists, try to load it
        if fileManager.fileExists(atPath: hostP12) {
            if let identity = loadIdentity(from: hostP12, label: keyLabel) {
                identityCache.setObject(identity, forKey: host as NSString)
                return identity
            }
        }
        
        // 1. Generate Host Key
        try await runOpenSSL(["genrsa", "-out", hostKey, "2048"])
        
        // 2. Generate Host CSR and Config with SAN & KeyUsage
        let hostConfigPath = certsDirectory.appendingPathComponent("\(hostClean).cnf").path
        let hostConfigContent = """
        [ req ]
        default_bits       = 2048
        distinguished_name = req_distinguished_name
        req_extensions     = req_ext
        prompt             = no
        
        [ req_distinguished_name ]
        CN = \(host)
        
        [ req_ext ]
        basicConstraints = critical, CA:FALSE
        keyUsage = critical, digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        
        [ alt_names ]
        DNS.1 = \(host)
        """
        try hostConfigContent.write(to: URL(fileURLWithPath: hostConfigPath), atomically: true, encoding: .utf8)

        try await runOpenSSL([
            "req", "-new",
            "-key", hostKey,
            "-out", hostCsr,
            "-config", hostConfigPath
        ])
        
        // 3. Sign Host Certificate with CA and Extensions
        try await runOpenSSL([
            "x509", "-req", "-days", "365",
            "-in", hostCsr,
            "-CA", caCertPath.path,
            "-CAkey", caKeyPath.path,
            "-set_serial", String(Int.random(in: 1...Int.max)),
            "-out", hostCert,
            "-extensions", "req_ext",
            "-extfile", hostConfigPath
        ])
        
        // 4. Package into PKCS12
        try await runOpenSSL([
            "pkcs12", "-export",
            "-in", hostCert,
            "-inkey", hostKey,
            "-out", hostP12,
            "-passout", "pass:ares"
        ])
        
        guard let identity = loadIdentity(from: hostP12, label: keyLabel) else {
            throw NSError(domain: "CertificateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load generated identity"])
        }
        
        identityCache.setObject(identity, forKey: host as NSString)
        return identity
    }
    
    private func loadIdentity(from p12Path: String, label: String) -> SecIdentity? {
        guard let p12Data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)) else { return nil }
        
        var options: [String: Any] = [kSecImportExportPassphrase as String: "ares"]
        
        // Create explicit access control for this app
        var trustedApp: SecTrustedApplication?
        let appStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApp)
        
        if appStatus == errSecSuccess, let app = trustedApp {
            var access: SecAccess?
            let accessStatus = SecAccessCreate("Ares Private Key" as CFString, [app] as CFArray, &access)
            if accessStatus == errSecSuccess, let acc = access {
                options[kSecImportExportAccess as String] = acc
            } else {
                print("[CertificateManager] ⚠️ Failed to create SecAccess: \(accessStatus)")
            }
        } else {
            print("[CertificateManager] ⚠️ Failed to create SecTrustedApplication: \(appStatus)")
        }
        
        // CRITICAL: Delete existing items with this specific label first
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        SecItemDelete(query as CFDictionary)

        var items: CFArray?
        let result = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        
        if result != errSecSuccess {
            print("[CertificateManager] ❌ SecPKCS12Import failed: \(result)")
            return nil
        }
        
        guard let itemsArray = items as? [[String: Any]],
              let firstItem = itemsArray.first else {
            print("[CertificateManager] ❌ Failed to extract items from imported P12")
            return nil
        }
        
        // Extract identity
        let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity
        
        // Update the Private Key with the specific Label so we can find/delete it later
        var privateKey: SecKey?
        if SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess, let key = privateKey {
             let updateQuery: [String: Any] = [
                 kSecValueRef as String: key,
                 kSecClass as String: kSecClassKey
             ]
             let updateAttributes: [String: Any] = [
                 kSecAttrLabel as String: label
             ]
             SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
             // print("[CertificateManager] 🏷️ Tagged key with label: \(label)")
        }
        
        return identity
    }
    
    private func runOpenSSL(_ arguments: [String]) async throws {
        await Task.yield() // Yield to allow concurrency and silence 'no await' warning
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        
        // Silence output
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "OpenSSL", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "OpenSSL failed with arguments: \(arguments)"])
        }
    }
    
    /// Exports Root CA to a location user can install
    func exportRootCA(to url: URL) async throws {
        if !fileManager.fileExists(atPath: caCertPath.path) {
            try await generateRootCA()
        }
        
        // Remove existing file at destination if needed
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        
        try fileManager.copyItem(at: caCertPath, to: url)
    }
    
    /// Installs the Root CA to user's keychain and opens Keychain Access for manual trust
    func installToKeychain() async throws {
        // Generate if needed
        if !fileManager.fileExists(atPath: caCertPath.path) {
            try await generateRootCA()
        }
        
        // Install to user's login keychain (no admin needed)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-trusted-cert",
            "-k", NSHomeDirectory() + "/Library/Keychains/login.keychain-db",
            caCertPath.path
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            
            // If it already exists, that's okay
            if !errorString.contains("already exists") && !errorString.contains("SEC_ERROR_") {
                throw NSError(
                    domain: "CertificateManager",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Command failed: \(errorString)"]
                )
            }
        }
        
        await MainActor.run { checkRootCA() }
    }
}


