import SwiftUI

struct MenuBarPreview: View {
    @State private var notice: String?
    var body: some View {
        MenuBarPanel(country: "US", ip: "104.194.8.56", latency: 915,
                     showsRisk: true, risk: 33,
                     download: "24.8 KB/s", upload: "1.2 KB/s",
                     openDashboard: { notice = "Dashboard" },
                     openActivity: { notice = "Activity" }, openSettings: { notice = "Settings" }, quit: { notice = "Quit" })
            .alert("Preview only", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("Done") { notice = nil }
            } message: { Text(notice ?? "") }
    }
}
