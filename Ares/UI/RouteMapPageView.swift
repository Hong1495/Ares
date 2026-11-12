import SwiftUI

struct RouteMapPageView: View {
    @StateObject private var model = RouteMapViewModel()
    var body: some View {
        RoutingPresentation(snapshot:model.snapshot,status:model.status)
            .navigationTitle("")
            .task { await model.monitor() }
    }
}
