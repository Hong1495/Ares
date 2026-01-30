import SwiftUI
import MapKit

// MARK: - Route Map View

struct RouteMapPageView: View {
    @EnvironmentObject var clashController: ClashController
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47), // Center on Shanghai (User Location)
        span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80) // Global view but centered
    ))

    // User Location (Simulated default to Beijing/Shanghai/HK for demo if not available)
    // In real app, use CoreLocation
    let localLocation = CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47) // Shanghai

    // Cache for simulated coordinates to avoid re-calculation and jitter
    @State private var coordinateCache: [String: CLLocationCoordinate2D] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                // 1. Draw Lines (Geodesic)
                ForEach(uniqueConnections, id: \.id) { conn in
                    MapPolyline(coordinates: [localLocation, conn.coordinate], contourStyle: .geodesic)
                        .stroke(
                            LinearGradient(
                                colors: [conn.color.opacity(0.9), conn.color.opacity(0.4)], // Increased opacity
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 3 // Thicker lines
                        )
                }

                // 2. Draw Target Nodes
                ForEach(uniqueConnections, id: \.id) { conn in
                    Annotation(conn.host, coordinate: conn.coordinate) {
                        Circle()
                            .fill(conn.color)
                            .frame(width: 8, height: 8)
                            .shadow(color: conn.color.opacity(0.5), radius: 4)
                    }
                }

                // 3. User Node
                Annotation("My Mac", coordinate: localLocation) {
                    Image(systemName: "macbook.and.iphone")
                        .foregroundColor(.blue)
                        .padding(6)
                        .background(Circle().fill(.white).shadow(radius: 2))
                }
            }
            .mapStyle(.standard) // Standard 2D map, adapts to light/dark automatically
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("Routing")
    }

    // Helper to deduplicate connections by simulating coordinates
    struct MapConnection: Identifiable {
        let id = UUID()
        let host: String
        let coordinate: CLLocationCoordinate2D
        let traffic: Int64
        let source: String
        let color: Color
    }

    var uniqueConnections: [MapConnection] {
        // We want to show distinct lines for distinct target IPs
        var map: [String: MapConnection] = [:]

        for chain in clashController.activeChains {
            let key = chain.destinationIP == "0.0.0.0" ? chain.host : chain.destinationIP
            let source = chain.sourceProcess.isEmpty ? "Unknown" : chain.sourceProcess

            // To properly show "Color per App", we might need multiple lines to the same location if different apps access it?
            // Prioritize: If multiple apps access the same IP, which color do we show?
            // Option 1: Overwrite (last one wins)
            // Option 2: Unique ID based on (IP + Source) -> Multiple lines to same dot?
            // Let's go with Option 1 for map clarity, or Option 2 if we want to see the "rainbow".
            // Implementation: Unique key = IP + Source
            let uniqueKey = "\(key)_\(source)"

            if map[uniqueKey] == nil {
                // Check cache or generate
                let coord = simulatedCoordinate(for: key) // Same coord for same IP
                let color = generateColor(for: source)
                map[uniqueKey] = MapConnection(host: chain.host, coordinate: coord, traffic: chain.download, source: source, color: color)
            }
        }
        return Array(map.values)
    }

    // Deterministic Random to simulate "Real" distribution for Eye Candy
    func simulatedCoordinate(for key: String) -> CLLocationCoordinate2D {
        // Check cache first (Not thread safe but okay for main thread UI)
        let hash = key.hashValue
        // Seeded random
        var seed = UInt64(bitPattern: Int64(hash))
        func next() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            // Modulo to keep range 0.0 - 1.0
            let m = seed % 1000
            return Double(m) / 1000.0
        }

        // Distribute mostly in US, EU, Asia regions
        let region = Int(next() * 3)
        var lat: Double
        var lon: Double

        if region == 0 { // US
            lat = 30 + next() * 20
            lon = -120 + next() * 50
        } else if region == 1 { // EU
            lat = 40 + next() * 15
            lon = 0 + next() * 30
        } else { // Asia (HK, JP, SG)
            lat = 10 + next() * 30
            lon = 100 + next() * 40
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // Stable Color Generator (Same as Topology)
    func generateColor(for string: String) -> Color {
        let hash = abs(string.hashValue)
        let colors: [Color] = [
            .blue, .red, .green, .orange, .purple, .pink, .cyan, .mint, .indigo, .teal
        ]
        return colors[hash % colors.count]
    }
}
