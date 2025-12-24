import SwiftUI

struct ConnectivityTestView: View {
    // Value: nil = not tested/loading, -1 = error/timeout, >0 = ms
    @State private var latencies: [String: Int] = [:] 
    @State private var loadingStates: [String: Bool] = [:]
    
    let sites = [
        ("Apple", "apple.com", "applelogo"),
        ("Github", "github.com", "network"),
        ("Google", "google.com", "globe"),
        ("Youtube", "youtube.com", "play.rectangle.fill")
    ]
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Connectivity")
                    .font(.headline)
                Spacer()
                Button(action: testAll) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(sites, id: \.0) { site in
                    VStack {
                        Image(systemName: site.2)
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(height: 30)
                        
                        Text(site.0)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        if loadingStates[site.0] == true {
                            ProgressView().scaleEffect(0.5)
                        } else if let ms = latencies[site.0] {
                            if ms < 0 {
                                Text("Error")
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                            } else {
                                Text("\(ms) ms")
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(ms < 200 ? .green : (ms < 500 ? .orange : .red))
                            }
                        } else {
                            Text("Test")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(8)
                    .contentShape(Rectangle()) // Make entire area tappable
                    .onTapGesture {
                        testSite(name: site.0, url: site.1)
                    }
                }
            }
        }
        .padding()
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task {
            await Task.yield()
            if latencies.isEmpty {
                testAll()
            }
        }
    }
    
    @MainActor
    func testAll() {
        for site in sites {
            testSite(name: site.0, url: site.1)
        }
    }
    
    @MainActor
    func testSite(name: String, url: String) {
        loadingStates[name] = true
        latencies[name] = nil // Clear previous result
        
        Task {
            // Retry logic for connectivity tests
            var finalLatency: Int? = nil
            let maxAttempts = 3
            for i in 1...maxAttempts { // 3 attempts
                if let latency = await measureLatency(url: url) {
                    finalLatency = latency
                    break
                }
                if i < maxAttempts {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2s
                }
            }
            
            let result = finalLatency ?? -1
            
            await MainActor.run {
                self.loadingStates[name] = false
                self.latencies[name] = result
            }
        }
    }
    
    private func measureLatency(url: String) async -> Int? {
        // Guard: Don't test if Clash is not running
        let isRunning = await MainActor.run { ClashViewModel.shared.isRunning }
        guard isRunning else { return nil }

        // Must use HTTPS to avoid ATS blocking
        guard let targetURL = URL(string: "https://\(url)") else { return nil }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0 // Slightly longer timeout for startup stability
        // Add cache policy to ensure real network request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let start = Date()
        
        do {
            // DIAGNOSTIC: Use shared session
            let session = URLSession.shared
            // let session = URLSession(configuration: .ephemeral, delegate: ConnectivityDelegate(), delegateQueue: nil)
            // defer { session.finishTasksAndInvalidate() }
            
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...499).contains(httpResponse.statusCode) {
                let elapsed = Date().timeIntervalSince(start)
                return Int(elapsed * 1000)
            }
            return nil
        } catch {
            let nsError = error as NSError
            print("[Connectivity] Error testing \(url): \(error.localizedDescription) (Code: \(nsError.code), Domain: \(nsError.domain))")
            return nil
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

