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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if loadingStates[site.0] == true {
                            ProgressView().scaleEffect(0.5)
                        } else if let ms = latencies[site.0] {
                            if ms < 0 {
                                Text("Error")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            } else {
                                Text("\(ms) ms")
                                    .font(.caption2)
                                    .foregroundStyle(ms < 200 ? .green : (ms < 500 ? .orange : .red))
                            }
                        } else {
                            Text("Test")
                                .font(.caption2)
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
    
    func testAll() {
        for site in sites {
            testSite(name: site.0, url: site.1)
        }
    }
    
    func testSite(name: String, url: String) {
        DispatchQueue.main.async {
            loadingStates[name] = true
            latencies[name] = nil // Clear previous result
        }
        
        Task {
            let latency = await measureLatency(url: url)
            await MainActor.run {
                DispatchQueue.main.async {
                    loadingStates[name] = false
                    latencies[name] = latency ?? -1 // -1 means error
                }
            }
        }
    }
    
    private func measureLatency(url: String) async -> Int? {
        // Guard: Don't test if Clash is not running
        let isRunning = ClashViewModel.shared.isRunning
        guard isRunning else { return nil }

        // Must use HTTPS to avoid ATS blocking
        guard let targetURL = URL(string: "https://\(url)") else { return nil }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0
        // Add cache policy to ensure real network request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let start = Date()
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 {
                let elapsed = Date().timeIntervalSince(start)
                return Int(elapsed * 1000)
            }
            return nil
        } catch {
            print("[Connectivity] Error testing \(url): \(error)")
            return nil
        }
    }
}
