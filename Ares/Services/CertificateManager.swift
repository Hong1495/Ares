import Foundation
import Security
import Combine

/// Manages certificates for MITM interception
final class CertificateManager: ObservableObject {
    static let shared = CertificateManager()
    
    private let fileManager = FileManager.default
    private var certsDirectory: URL {
        let appSupport = Self.applicationSupportDirectory(fileManager: fileManager)
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

    // Delegate identity generation to an actor to prevent race conditions and key deletion
    private let generator: IdentityGenerator

    private init() {
        let appSupport = Self.applicationSupportDirectory()
        let aresDir = appSupport.appendingPathComponent("Ares")
        let certsDir = aresDir.appendingPathComponent("Certs")
        try? FileManager.default.createDirectory(at: certsDir, withIntermediateDirectories: true)
        
        self.generator = IdentityGenerator(certsDirectory: certsDir)
        
        Task {
            await MainActor.run { self.checkRootCA() }
            await self.cleanupLegacyCerts()
            // Pre-generate certificates for common domains to avoid first-visit latency
            await self.pregenerateCommonCerts()
        }
    }

    private static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }
    
    /// Pre-generate certificates for commonly accessed domains
    private func pregenerateCommonCerts() async {
        // Only pregenerate if Root CA exists
        guard fileManager.fileExists(atPath: caCertPath.path) else { return }
        
        let commonDomains = [
            "google.com", "googleapis.com", "gstatic.com",
            "github.com", "githubusercontent.com",
            "cloudflare.com", "cdn.jsdelivr.net",
            "anthropic.com", "openai.com"
        ]
        
        for domain in commonDomains {
            // Run in background, don't block
            Task.detached(priority: .background) {
                _ = try? await self.getIdentity(for: domain)
            }
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
    }

    /// Generates a new Root CA with proper extensions
    func generateRootCA() async throws {
        // Delegate to actor to ensure serialization and prevent race conditions
        try await generator.forceRegenerateRootCA()
        await MainActor.run { checkRootCA() }
    }
    
    /// Gets (or generates) a SecIdentity for a specific host
    func getIdentity(for host: String) async throws -> SecIdentity {
        // Delegation entirely to actor, which handles race conditions
        return try await generator.getIdentity(for: host)
    }
    
    // Internal Actor to handle serialized identity generation
    actor IdentityGenerator {
        private let certsDirectory: URL
        // Persistent cache to ensure SecIdentity remains valid and keys are not deleted
        private var identityCache: [String: SecIdentity] = [:]
        private var inflightIdentities: [String: Task<SecIdentity, Error>] = [:]
        
        private var caCertPath: URL { certsDirectory.appendingPathComponent("ca.crt") }
        private var caKeyPath: URL { certsDirectory.appendingPathComponent("ca.key") }
        private var openSSLConfigPath: URL { certsDirectory.appendingPathComponent("openssl.cnf") }
        
        init(certsDirectory: URL) {
            self.certsDirectory = certsDirectory
        }
        
        func forceRegenerateRootCA() async throws {
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
            
            // Invalidate caches
            identityCache.removeAll()
        }
        
        func ensureRootCA() async throws {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: caCertPath.path) && fileManager.fileExists(atPath: caKeyPath.path) {
                return
            }
            try await forceRegenerateRootCA()
        }

        func getIdentity(for host: String) async throws -> SecIdentity {
            // Ensure CA exists safely
            try await ensureRootCA()
            
            // 1. Check Cache
            if let cached = identityCache[host] {
                return cached
            }
            
            // 2. Check In-flight Tasks
            if let task = inflightIdentities[host] {
                return try await task.value
            }
            
            // 3. Create new task
            let task = Task { () -> SecIdentity in
                defer { self.inflightIdentities.removeValue(forKey: host) }
                return try await self._getIdentity(for: host)
            }
            
            inflightIdentities[host] = task
            let identity = try await task.value
            identityCache[host] = identity
            return identity
        }
        private func _getIdentity(for host: String) async throws -> SecIdentity {
            // Use FileManager from non-isolated context if needed, but actor isolation is fine here
            let fileManager = FileManager.default
            
            let hostClean = host.replacingOccurrences(of: "*", with: "wildcard")
            let hostKey = certsDirectory.appendingPathComponent("\(hostClean).key").path
            let hostCsr = certsDirectory.appendingPathComponent("\(hostClean).csr").path
            let hostCert = certsDirectory.appendingPathComponent("\(hostClean).crt").path
            let hostP12 = certsDirectory.appendingPathComponent("\(hostClean).p12").path
            let keyLabel = "Ares-Key-\(host)"
            
            // If P12 exists, try to load it first (avoid regeneration)
            if fileManager.fileExists(atPath: hostP12) {
                if let identity = loadIdentity(from: hostP12, label: keyLabel) {
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
            
            return identity
        }
        
        private func loadIdentity(from p12Path: String, label: String) -> SecIdentity? {
            guard let p12Data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)) else {
                return nil
            }
            
            var items: CFArray?
            let options: [String: Any] = [
                kSecImportExportPassphrase as String: "ares"
            ]
            
            let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
            
            if status == errSecSuccess,
               let items,
               CFArrayGetCount(items) > 0,
               let item = CFArrayGetValueAtIndex(items, 0) {
                let dictionary = unsafeBitCast(item, to: CFDictionary.self)
                let identityKey = Unmanaged.passUnretained(kSecImportItemIdentity).toOpaque()
                if let identityValue = CFDictionaryGetValue(dictionary, identityKey) {
                    let identity = unsafeBitCast(identityValue, to: SecIdentity.self)
                    var certificate: SecCertificate?
                    if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess {
                        return identity
                    }
                }
            }

            return nil
        }
        
        private func runOpenSSL(_ arguments: [String]) async throws {
            await Task.yield()
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = arguments
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                // Read stderr to capture error details if it fails
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if process.terminationStatus != 0 {
                    let errorStr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown OpenSSL Error"
                    throw NSError(domain: "OpenSSL", code: Int(process.terminationStatus), 
                                userInfo: [NSLocalizedDescriptionKey: "OpenSSL Failed: \(errorStr). Args: \(arguments)"])
                }
            } catch {
                throw error
            }
        }
    }
    
    private func runOpenSSL(_ arguments: [String]) async throws {
         // Facade for outer class usage (like Root CA generation)
        await Task.yield()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorStr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown OpenSSL Error"
                throw NSError(domain: "OpenSSL", code: Int(process.terminationStatus), 
                            userInfo: [NSLocalizedDescriptionKey: "OpenSSL Failed: \(errorStr). Args: \(arguments)"])
            }
        } catch {
            throw error
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
        
        // Install to user's login keychain with explicit trust settings
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-trusted-cert",
            "-r", "trustRoot",          // Trust as Root CA
            "-p", "ssl",                // Trust for SSL
            "-p", "basic",              // Trust for Basic Policy
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
