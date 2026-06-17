import SwiftUI

struct HeadersInspector: View {
    let request: BrowserRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General
                SectionView(title: "General") {
                    KeyValueRow(key: "Request URL", value: request.url)
                    KeyValueRow(key: "Request Method", value: request.method)
                    KeyValueRow(key: "Status Code", value: "\(request.statusCode ?? 0) \(request.status.rawValue)")
                    KeyValueRow(key: "Remote Address", value: request.remoteAddress ?? "-")
                }

                // Response Headers
                if let headers = request.responseHeaders {
                    SectionView(title: "Response Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            KeyValueRow(key: key, value: value)
                        }
                    }
                }

                // Request Headers
                if let headers = request.requestHeaders {
                    SectionView(title: "Request Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            KeyValueRow(key: key, value: value)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct PayloadInspector: View {
    let request: BrowserRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Query String Parameters always on top if present
            if let urlComponents = URLComponents(string: request.url), let items = urlComponents.queryItems, !items.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        SectionView(title: "Query String Parameters") {
                            ForEach(items, id: \.name) { item in
                                KeyValueRow(key: item.name, value: item.value ?? "")
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 150) // Limit height for query params
                Divider()
            }

            if let body = request.requestBody, !body.isEmpty {
                // Use unified JSON detection logic
                if body.looksLikeJSON {
                     // Full screen JSON with preprocessing
                     JSONTreeView(jsonString: body.preprocessJSON)
                 } else {
                     ScrollView {
                         BodyTextView(text: body)
                            .padding()
                     }
                 }
            } else {
                EmptyState(text: "No Request Payload")
            }
        }
    }
}

struct PreviewInspector: View {
    let request: BrowserRequest

    var body: some View {
         RichContentPreview(request: request)
    }
}

struct ResponseInspector: View {
    let request: BrowserRequest

    var body: some View {
        RichContentPreview(request: request)
    }
}
