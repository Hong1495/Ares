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
        ZStack {
            // Background color that adapts to light/dark
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            MutedWorldMapView(position: $position, connections: uniqueConnections, localLocation: localLocation)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .padding(1) // Minor padding for shadow safety
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("Routing")
        .onAppear {
            Task { await clashController.monitorConnections() }
        }
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

// MARK: - MutedWorldMapView

struct MutedWorldMapView: NSViewRepresentable {
    @Binding var position: MapCameraPosition
    let connections: [RouteMapPageView.MapConnection]
    let localLocation: CLLocationCoordinate2D

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.configure(mapView)

        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        context.coordinator.configure(nsView)
        updateOverlays(in: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func updateOverlays(in mapView: MKMapView) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // Draw Geodesic Lines
        for conn in connections {
            let coords = [localLocation, conn.coordinate]
            let polyline = MKGeodesicPolyline(coordinates: coords, count: 2)
            mapView.addOverlay(polyline)

            // Add Node Annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = conn.coordinate
            annotation.title = conn.host
            mapView.addAnnotation(annotation)
        }

        // Add Local User Annotation
        let localAnn = MKPointAnnotation()
        localAnn.coordinate = localLocation
        localAnn.title = "Me"
        mapView.addAnnotation(localAnn)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MutedWorldMapView
        private var didConfigure = false

        init(_ parent: MutedWorldMapView) {
            self.parent = parent
        }

        func configure(_ mapView: MKMapView) {
            guard !didConfigure else { return }
            didConfigure = true

            // 1. Globe Mode Configuration
            // Standard (realistic) is more stable on macOS and still supports globe zoom.
            let config = MKStandardMapConfiguration(elevationStyle: .realistic)
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            config.emphasisStyle = .muted
            mapView.preferredConfiguration = config

            // 2. Interaction Tweaks
            mapView.isZoomEnabled = true
            mapView.isScrollEnabled = true
            mapView.isPitchEnabled = true // Required for globe feel
            mapView.isRotateEnabled = true

            // 3. Set Initial Global View
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47),
                fromDistance: 40_000_000, // 40,000 km altitude for full globe
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue.withAlphaComponent(0.6)
                renderer.lineWidth = 1.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "NodeMarker"
            var marker = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if marker == nil {
                marker = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }

            if annotation.title == "Me" {
                marker?.glyphImage = NSImage(systemSymbolName: "macbook.and.iphone", accessibilityDescription: nil)
                marker?.markerTintColor = .systemBlue
            } else {
                marker?.glyphImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
                marker?.markerTintColor = .systemGray
            }

            marker?.displayPriority = .required
            marker?.subtitleVisibility = .hidden
            marker?.titleVisibility = .hidden

            return marker
        }
    }
}
