import SwiftUI

/// Test Card for speed/latency testing
struct TestCard: View {
    @EnvironmentObject var clashController: ClashController
    @State private var isTesting = false
    @State private var testResults: [String: Int] = [:]
    @State private var testProgress: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Connection Test", systemImage: "speedometer")
                    .font(.headline)
                
                Spacer()
                
                if isTesting {
                    ProgressView(value: testProgress)
                        .frame(width: 100)
                }
            }
            
            Spacer()
            
            if testResults.isEmpty && !isTesting {
                VStack(spacing: 8) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No test results yet")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if !testResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(testResults.sorted(by: { $0.value < $1.value }).prefix(5)), id: \.key) { name, delay in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(delayColor(delay))
                                        .frame(width: 6, height: 6)
                                    Text("\(delay)ms")
                                        .font(.footnote)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            HStack(spacing: 8) {
                Button {
                    Task {
                        await testAllNodes()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Test All Nodes")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)
                
                Button {
                    Task {
                        await testActiveGroup()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("Test Active Group")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)
            }
        }
        .padding()
        .frame(height: 180)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func testAllNodes() async {
        isTesting = true
        testResults.removeAll()
        testProgress = 0
        
        let allNodes = Array(clashController.proxyNodes.keys)
        let total = Double(allNodes.count)
        
        for (index, nodeName) in allNodes.enumerated() {
            do {
                let delay = try await clashController.testProxyDelay(name: nodeName)
                testResults[nodeName] = delay
            } catch {
                // Skip failed nodes
            }
            testProgress = Double(index + 1) / total
        }
        
        isTesting = false
    }
    
    private func testActiveGroup() async {
        isTesting = true
        testResults.removeAll()
        testProgress = 0
        
        // Get first group
        guard let firstGroup = clashController.proxyGroups.first else {
            isTesting = false
            return
        }
        
        let nodes = firstGroup.all
        let total = Double(nodes.count)
        
        for (index, nodeName) in nodes.enumerated() {
            do {
                let delay = try await clashController.testProxyDelay(name: nodeName)
                testResults[nodeName] = delay
            } catch {
                // Skip failed
            }
            testProgress = Double(index + 1) / total
        }
        
        isTesting = false
    }
    
    private func delayColor(_ ms: Int) -> Color {
        switch ms {
        case 0..<100: return .green
        case 100..<300: return .orange
        default: return .red
        }
    }
}
