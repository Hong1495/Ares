import SwiftUI
import WebKit

/// Local, nonpersistent renderer. Live route data never enters a URL or remote page.
struct RoutingMapSurface: NSViewRepresentable {
    let snapshot: RouteSnapshot
    @Binding var selection: String?
    let dark: Bool
    let command: String
    let revision: Int
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name:"status")
        config.userContentController.add(context.coordinator, name:"selection")
        let web = WKWebView(frame:.zero,configuration:config)
        web.navigationDelegate = context.coordinator
        do {
            func resource(_ name: String, _ ext: String) throws -> String {
                guard let url = Bundle.main.url(forResource:name,withExtension:ext) else { throw CocoaError(.fileNoSuchFile) }
                return try String(contentsOf:url,encoding:.utf8)
            }
            let html = try resource("routing-map","html")
                .replacingOccurrences(of:"__RENDERER__",with:resource("routing-maplibre","js"))
                .replacingOccurrences(of:"__WORLD__",with:resource("routing-world","json"))
                .replacingOccurrences(of:"__GEOMETRY__",with:resource("routing-geometry","js"))
            web.loadHTMLString(html,baseURL:nil)
        } catch { Task { @MainActor in self.error = "Map resources could not be loaded." } }
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(web)
    }
    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading(); web.configuration.userContentController.removeAllScriptMessageHandlers()
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: RoutingMapSurface
        var loaded = false
        struct MapEndpoint: Encodable, Equatable { let location: RouteLocation? }
        struct MapRoute: Encodable, Equatable { let id: String; let endpoints: [MapEndpoint] }
        struct MapSnapshot: Encodable { let routes: [MapRoute] }
        var lastRoutes: [MapRoute]?
        var lastSelection: String?
        var lastDark: Bool?
        var lastRevision = -1
        init(_ parent: RoutingMapSurface) { self.parent = parent }
        func call(_ web: WKWebView, _ body: String, _ arguments: [String:Any]) {
            web.callAsyncJavaScript(body,arguments:arguments,in:nil,in:.page) { [weak self] result in
                if case .failure = result { self?.parent.error = "Map could not update. Reopen Routing to retry." }
            }
        }
        func sync(_ web: WKWebView) {
            guard loaded else { return }
            let routes = parent.snapshot.routes.map { MapRoute(id:$0.id,endpoints:$0.endpoints.map { MapEndpoint(location:$0.location) }) }
            if lastRoutes != routes {
                lastRoutes = routes
                if let data = try? JSONEncoder().encode(MapSnapshot(routes:routes)), let object = try? JSONSerialization.jsonObject(with:data) {
                    call(web,"window.setSnapshot(value)",["value":object])
                }
            }
            if lastDark != parent.dark { lastDark=parent.dark; call(web,"window.setAppearance(value)",["value":parent.dark]) }
            if lastSelection != parent.selection {
                lastSelection=parent.selection; call(web,"window.selectRoute(value)",["value":parent.selection as Any? ?? NSNull()])
            }
            if lastRevision != parent.revision {
                lastRevision=parent.revision;call(web,"window.mapCommand(value)",["value":parent.command])
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded=true;sync(webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.error="Map could not load." }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.error="Map renderer stopped. Reopen Routing to retry." }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }
            if message.name == "selection", parent.snapshot.routes.contains(where:{$0.id==text}) { parent.selection=text }
            else if message.name == "status" { parent.error = text == "ready" ? nil : text }
        }
    }
}
