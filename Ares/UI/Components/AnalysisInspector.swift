import SwiftUI

struct AnalysisInspector: View {
    let request: BrowserRequest
    @State private var copiedCurl = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // Advanced Action Bar
                HStack {
                    Text("Developer Diagnosis")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        let curl = request.generateCurl()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curl, forType: .string)
                        copiedCurl = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCurl = false }
                    } label: {
                        Label(copiedCurl ? "Copied cURL" : "Copy as cURL", systemImage: "terminal.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Security Analysis
                SectionView(title: "Security Analysis") {
                    let issues = request.securityIssues
                    if issues.isEmpty {
                        Label("No obvious security checks failed.", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(issues, id: \.self) { issue in
                                Label(issue, systemImage: "exclamationmark.shield")
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                
                // Performance Analysis
                SectionView(title: "Performance & Quality") {
                    let insights = request.performanceInsights
                    if insights.isEmpty {
                         Label("No performance issues detected.", systemImage: "hare.fill")
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(insights, id: \.self) { insight in
                                Label(insight, systemImage: "speedometer")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                
                // Token / Auth Analysis (If applicable)
                if let auth = request.requestHeaders?["Authorization"] {
                    SectionView(title: "Authorization") {
                        VStack(alignment: .leading) {
                            Text("Token Present")
                                .font(.caption).bold()
                            Text(auth.prefix(30) + "...")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
