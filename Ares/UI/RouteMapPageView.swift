import SwiftUI
import MapKit

// MARK: - Route Map View

struct RouteMapPageView: View {
    @EnvironmentObject var clashController: ClashController
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 160, longitudeDelta: 360)
    ))

    // User Location (Simulated default to Beijing/Shanghai/HK for demo if not available)
    // In real app, use CoreLocation
    let localLocation = CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47) // Shanghai

    // Cache for simulated coordinates to avoid re-calculation and jitter
    @State private var coordinateCache: [String: CLLocationCoordinate2D] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1000, maximumDistance: 400_000_000)) {
                // 1. Draw Lines (Geodesic)
                ForEach(uniqueConnections, id: \.id) { conn in
                    MapPolyline(coordinates: [localLocation, conn.coordinate], contourStyle: .geodesic)
                        .stroke(
                            LinearGradient(
                                colors: [conn.color.opacity(0.8), conn.color.opacity(0.3)], // Slightly reduced opacity for elegance
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5 // Refined: Slightly thicker lines (User Choice)
                        )
                }

                // 2. Draw Target Nodes
                ForEach(uniqueConnections, id: \.id) { conn in
                    Annotation(conn.host, coordinate: conn.coordinate) {
                        Circle()
                            .fill(conn.color)
                            .frame(width: 6, height: 6) // Smaller nodes
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5)) // Adaptive border
                            .shadow(radius: 2)
                    }
                }

                // 3. User Node
                Annotation("My Mac", coordinate: localLocation) {
                    Image(systemName: "macbook.and.iphone")
                        .foregroundColor(.white) // White for contrast on Satellite
                        .padding(6)
                        .background(Circle().fill(.blue).shadow(radius: 2))
                }
            }
            .mapStyle(.standard) // Reverted to 2D Standard per user request
            .mapControlVisibility(.hidden) // Keep controls hidden for clean UI
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

    // MARK: - Safe Coordinate Simulation (City Snapping)

    struct CityLocation {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    // Major Internet Hubs (Guaranteed Land)
    let globalHubs: [CityLocation] = [
        // US
        CityLocation(name: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
        CityLocation(name: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)),
        CityLocation(name: "Ashburn (AWS)", coordinate: CLLocationCoordinate2D(latitude: 39.0438, longitude: -77.4874)),
        CityLocation(name: "Dallas", coordinate: CLLocationCoordinate2D(latitude: 32.7767, longitude: -96.7970)),

        // Europe
        CityLocation(name: "London", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)),
        CityLocation(name: "Frankfurt", coordinate: CLLocationCoordinate2D(latitude: 50.1109, longitude: 8.6821)),
        CityLocation(name: "Amsterdam", coordinate: CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041)),
        CityLocation(name: "Paris", coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)),

        // Asia
        CityLocation(name: "Tokyo", coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)),
        CityLocation(name: "Singapore", coordinate: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198)),
        CityLocation(name: "Hong Kong", coordinate: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)),
        CityLocation(name: "Taipei", coordinate: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)),
        CityLocation(name: "Seoul", coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)),

        // Oceania
        CityLocation(name: "Sydney", coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093))
    ]

    func simulatedCoordinate(for key: String) -> CLLocationCoordinate2D {
        // Deterministic City Selection
        // This ensures points are ALWAYS on land (known cities)
        // and grouped logically like real internet traffic
        let hash = abs(key.hashValue)
        let index = hash % globalHubs.count

        // Add a TINY random jitter so points overlaying the same city
        // show as a cluster rather than a single dot
        let city = globalHubs[index]

        // Jitter: +/- 0.5 degree (approx 50km) - keeps it near the city but distinct
        var seed = UInt64(bitPattern: Int64(hash))
        seed ^= seed << 13
        seed ^= seed >> 7
        let jitterLat = (Double(seed % 100) / 100.0 - 0.5) * 0.5
        let jitterLon = (Double((seed >> 10) % 100) / 100.0 - 0.5) * 0.5

        return CLLocationCoordinate2D(
            latitude: city.coordinate.latitude + jitterLat,
            longitude: city.coordinate.longitude + jitterLon
        )
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
