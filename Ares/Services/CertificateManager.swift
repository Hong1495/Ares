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

    // Delegate identity generation to an actor to prevent race conditions and key deletion
    private let generator: IdentityGenerator

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let aresDir = appSupport.appendingPathComponent("Ares")
        let certsDir = aresDir.appendingPathComponent("Certs")
        try? FileManager.default.createDirectory(at: certsDir, withIntermediateDirectories: true)
        
        self.generator = IdentityGenerator(certsDirectory: certsDir)
        
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
    
    /// Gets (or generates) a SecIdentity for a specific host
    func getIdentity(for host: String) async throws -> SecIdentity {
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
        
        // Temporary keychain to avoid permission prompts
        private var tempKeychain: SecKeychain?
        private var tempKeychainPath: String { certsDirectory.appendingPathComponent("ares-mitm.keychain-db").path }
        
        init(certsDirectory: URL) {
            self.certsDirectory = certsDirectory
        }
        
        /// Gets or creates a temporary, password-less Keychain to avoid user prompts
        /// Uses security CLI for complete control over keychain settings
        private func getOrCreateTempKeychain() throws -> SecKeychain {
            // Return cached keychain if available
            if let kc = tempKeychain {
                // Always unlock before returning
                SecKeychainUnlock(kc, 0, "", true)
                return kc
            }
            
            let path = tempKeychainPath
            
            // First, delete any existing keychain to start fresh
            if FileManager.default.fileExists(atPath: path) {
                // Try to delete using security CLI
                let deleteProcess = Process()
                deleteProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                deleteProcess.arguments = ["delete-keychain", path]
                deleteProcess.standardOutput = FileHandle.nullDevice
                deleteProcess.standardError = FileHandle.nullDevice
                try? deleteProcess.run()
                deleteProcess.waitUntilExit()
                
                // Also delete file directly if still exists
                try? FileManager.default.removeItem(atPath: path)
            }
            
            // Create new keychain using security CLI with empty password
            let createProcess = Process()
            createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            createProcess.arguments = ["create-keychain", "-p", "", path]
            createProcess.standardOutput = FileHandle.nullDevice
            createProcess.standardError = FileHandle.nullDevice
            
            try createProcess.run()
            createProcess.waitUntilExit()
            
            if createProcess.terminationStatus != 0 {
                throw NSError(domain: "CertificateManager", code: Int(createProcess.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "security create-keychain failed"])
            }
            
            // Disable auto-lock (set timeout to 0 = no lock)
            let settingsProcess = Process()
            settingsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            settingsProcess.arguments = ["set-keychain-settings", "-t", "0", "-u", path]
            settingsProcess.standardOutput = FileHandle.nullDevice
            settingsProcess.standardError = FileHandle.nullDevice
            try? settingsProcess.run()
            settingsProcess.waitUntilExit()
            
            // Unlock the keychain
            let unlockProcess = Process()
            unlockProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            unlockProcess.arguments = ["unlock-keychain", "-p", "", path]
            unlockProcess.standardOutput = FileHandle.nullDevice
            unlockProcess.standardError = FileHandle.nullDevice
            try? unlockProcess.run()
            unlockProcess.waitUntilExit()
            
            // Open with Security framework for SecItemCopyMatching
            var keychain: SecKeychain?
            let openStatus = SecKeychainOpen(path, &keychain)
            if openStatus != errSecSuccess {
                throw NSError(domain: "CertificateManager", code: Int(openStatus),
                    userInfo: [NSLocalizedDescriptionKey: "SecKeychainOpen failed: \(openStatus)"])
            }
            
            guard let kc = keychain else {
                throw NSError(domain: "CertificateManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Keychain is nil"])
            }
            
            // Final unlock with Security framework
            SecKeychainUnlock(kc, 0, "", true)
            
            tempKeychain = kc
            print("[CertificateManager] 🔐 Created new temp Keychain via CLI (no password, no lock)")
            return kc
        }
        
        func getIdentity(for host: String) async throws -> SecIdentity {
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
            // APPROACH: Don't use Keychain at all. Load PKCS12 directly into memory.
            // SecPKCS12Import on macOS actually DOES add to Keychain internally,
            // but we can import without access control by using kSecImportToMemoryOnly (iOS only).
            // 
            // For macOS, we need to parse the PKCS12 ourselves or accept the Keychain behavior.
            // The trick is to use SecPKCS12Import with a temporary keychain that's already unlocked.
            
            guard let p12Data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)) else {
                print("[CertificateManager] ❌ Cannot read P12 file")
                return nil
            }
            
            // Try the standard import with a permissive access control
            // Create an "allow all" access control so no prompts are triggered
            var access: SecAccess?
            let accessStatus = SecAccessCreate("Ares MITM Key" as CFString, nil, &access)
            
            var items: CFArray?
            var options: [String: Any] = [
                kSecImportExportPassphrase as String: "ares"
            ]
            
            // Add permissive access if successfully created
            if accessStatus == errSecSuccess, let acc = access {
                options[kSecImportExportAccess as String] = acc
            }
            
            let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
            
            if status == errSecSuccess,
               let itemsArray = items as? [[String: Any]],
               let firstItem = itemsArray.first,
               let identity = firstItem[kSecImportItemIdentity as String] {
                
                // Success! The import worked
                print("[CertificateManager] ✅ Loaded identity via SecPKCS12Import with permissive access")
                return (identity as! SecIdentity)
            }
            
            // If SecPKCS12Import failed, try alternative: use a temp keychain as default
            print("[CertificateManager] ⚠️ SecPKCS12Import failed (\(status)), trying temp keychain approach")
            
            do {
                let keychain = try getOrCreateTempKeychain()
                
                // Save original default keychain
                var originalDefault: SecKeychain?
                SecKeychainCopyDefault(&originalDefault)
                
                // Set temp keychain as default (SecPKCS12Import uses default)
                SecKeychainSetDefault(keychain)
                
                // Now try import again - it should go to our temp keychain
                var items2: CFArray?
                let status2 = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items2)
                
                // Restore original default
                if let orig = originalDefault {
                    SecKeychainSetDefault(orig)
                }
                
                if status2 == errSecSuccess,
                   let itemsArray = items2 as? [[String: Any]],
                   let firstItem = itemsArray.first,
                   let identity = firstItem[kSecImportItemIdentity as String] {
                    print("[CertificateManager] ✅ Loaded identity via temp Keychain")
                    return (identity as! SecIdentity)
                }
                
                print("[CertificateManager] ❌ Both import methods failed: \(status2)")
                return nil
                
            } catch {
                print("[CertificateManager] ❌ Failed: \(error)")
                return nil
            }
        }
        
        private func runOpenSSL(_ arguments: [String]) async throws {
            await Task.yield()
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = arguments
            
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                throw NSError(domain: "OpenSSL", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "OpenSSL failed with arguments: \(arguments)"])
            }
        }
    }
    
    private func runOpenSSL(_ arguments: [String]) async throws {
         // Facade for outer class usage (like Root CA generation)
         // Note: Code duplication is acceptable here to keep Actor isolated
        await Task.yield()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        
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


