import SwiftUI

struct ConnectivityTestView: View {
    // Value: nil = not tested/loading, -1 = error/timeout, >0 = ms
    @State private var latencies: [String: Int] = [:] 
    @State private var loadingStates: [String: Bool] = [:]
    
    let sites = [
        ("Gateway", "http://10.10.24.111", "server.rack"),
        ("Google", "https://www.google.com", "globe"),
        ("Github", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        ("Gemini", "https://gemini.google.com", "sparkles")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label {
                    Text("Connectivity")
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .fontWeight(.light)
                        .frame(width: 20)
                }
                .font(.headline.weight(.medium))
                
                Spacer()
                
                // Auto-refresh only
            }
            .frame(height: 24) // Standard Header Height
            
            Divider()
            
            Spacer()
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(sites, id: \.0) { site in
                    VStack(spacing: 4) {
                        Image(systemName: site.2)
                            .font(.title3) // Slightly smaller icon
                            .foregroundStyle(.primary)
                            .frame(height: 24)
                        
                        Text(site.0)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        if loadingStates[site.0] == true {
                            ProgressView().scaleEffect(0.5)
                                .frame(height: 16)
                        } else if let ms = latencies[site.0] {
                            if ms < 0 {
                                Text("Err")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)
                            } else {
                                Text("\(ms)ms")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundStyle(ms < 200 ? .green : (ms < 500 ? .orange : .red))
                            }
                        } else {
                            Text("Test")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    // Manual retry removed as requested
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            startMonitoring()
        }
    }
    
    @State private var retryTask: Task<Void, Never>?
    
    // ... (keep body until .task) ...
    // NOTE: Due to length limits, I need to be precise. 
    // The previous body code ends at .task.
    // I will replace `testAll` and `testSite` with a robust continuous loop mechanism, 
    // and trigger it from .task.
    
    // Actually the user wants "Connectivity... auto recovery".
    // This implies if a site fails, it should retry.
    // If all pass, should it keep testing? Probably periodically (e.g. every 30s) to keep status fresh?
    // "Regularly fetch" (定期获取) was requested.
        
    @MainActor
    func startMonitoring() {
        retryTask?.cancel()
        retryTask = Task {
            // Initial delay
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            while !Task.isCancelled {
                // Check if Clash is running
                if !ClashViewModel.shared.isRunning {
                     try? await Task.sleep(nanoseconds: 2_000_000_000)
                     continue
                }

                await testAll()
                
                // Wait for next cycle (e.g. 15 seconds)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    @MainActor
    func testAll() async {
        await withTaskGroup(of: Void.self) { group in
            for site in sites {
                group.addTask {
                    await testSite(name: site.0, url: site.1)
                }
            }
        }
    }
    
    @MainActor
    func testSite(name: String, url: String) async {
        // If already loading, skip? No, force refresh.
        loadingStates[name] = true
        // latencies[name] = nil // Don't clear old value during refresh, looks cleaner
        
        var finalLatency: Int? = nil
        // 2 attempts
        for _ in 1...2 { 
            if let latency = await measureLatency(url: url) {
                finalLatency = latency
                break
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        let result = finalLatency ?? -1
        self.loadingStates[name] = false
        withAnimation {
            self.latencies[name] = result
        }
    }
    
    private func measureLatency(url: String) async -> Int? {
        let isRunning = await MainActor.run { ClashViewModel.shared.isRunning }
        guard isRunning else { return nil }

        // Smart scheme handling
        var urlString = url
        if !urlString.hasPrefix("http") {
             urlString = "https://\(urlString)"
        }
        
        guard let targetURL = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3.0 // Snappy timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let start = Date()
        
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3.0
            let session = URLSession(configuration: config)
            
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...499).contains(httpResponse.statusCode) {
                let elapsed = Date().timeIntervalSince(start)
                return Int(elapsed * 1000)
            }
            return nil
        } catch {
            return nil // silent fail
        }
    }
}

/// Delegate to pin/trust the internal MITM Root CA
class ConnectivityDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            
            // Allow if it's our own MITM CA
            let caPath = CertificateManager.shared.rootCAPath.path
            if let caData = try? Data(contentsOf: URL(fileURLWithPath: caPath)),
               let caCert = SecCertificateCreateWithData(nil, caData as CFData) {
                
                // Set our CA as the anchor
                SecTrustSetAnchorCertificates(serverTrust, [caCert] as CFArray)
                SecTrustSetAnchorCertificatesOnly(serverTrust, false) // Allow system roots too
                
                var error: CFError?
                if SecTrustEvaluateWithError(serverTrust, &error) {
                    print("[Connectivity] ✅ Trust evaluation succeeded for internal CA")
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                } else {
                     print("[Connectivity] ❌ Trust evaluation failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }

        
        // Fallback to default handling
        completionHandler(.performDefaultHandling, nil)
    }
}

