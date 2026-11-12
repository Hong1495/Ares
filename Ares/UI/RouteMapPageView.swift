import SwiftUI
import MapKit

// MARK: - Route Map Page

struct RouteMapPageView: View {
    @EnvironmentObject var clashController: ClashController
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 160, longitudeDelta: 360)
    ))

    let localLocation = CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47)

    @State private var coordinateCache: [String: CLLocationCoordinate2D] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            DS.canvas

            MutedWorldMapView(
                position: $position,
                connections: uniqueConnections,
                localLocation: localLocation
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: DS.hairline)
            )
            .overlay(alignment: .topLeading) {
                Label(
                    "Illustrative layout — endpoint positions are not geolocated",
                    systemImage: "info.circle"
                )
                .font(DS.Typography.metadata)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .padding(DS.Space.md)
            }
            .overlay {
                if uniqueConnections.isEmpty {
                    ContentUnavailableView(
                        "No active routes",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Route activity appears here while connections are open.")
                    )
                }
            }
        }
        .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.lg)
            .padding(.top, DS.Space.pageTop)
        .navigationTitle("Routing")
        .onAppear {
            Task { await clashController.monitorConnections() }
        }
    }

    struct MapConnection: Identifiable {
        let id = UUID()
        let host: String
        let coordinate: CLLocationCoordinate2D
        let traffic: Int64
        let source: String
        let color: Color
    }

    var uniqueConnections: [MapConnection] {
        var map: [String: MapConnection] = [:]

        for chain in clashController.activeChains {
            let key = chain.destinationIP == "0.0.0.0" ? chain.host : chain.destinationIP
            let source = chain.sourceProcess.isEmpty ? "Unknown" : chain.sourceProcess
            let uniqueKey = "\(key)_\(source)"

            if map[uniqueKey] == nil {
                map[uniqueKey] = MapConnection(
                    host: chain.host,
                    coordinate: simulatedCoordinate(for: key),
                    traffic: chain.download,
                    source: source,
                    color: generateColor(for: source)
                )
            }
        }
        return Array(map.values)
    }

    // MARK: - Coordinates

    struct CityLocation {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    let globalHubs: [CityLocation] = [
        CityLocation(name: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
        CityLocation(name: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)),
        CityLocation(name: "Ashburn", coordinate: CLLocationCoordinate2D(latitude: 39.0438, longitude: -77.4874)),
        CityLocation(name: "Dallas", coordinate: CLLocationCoordinate2D(latitude: 32.7767, longitude: -96.7970)),
        CityLocation(name: "London", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)),
        CityLocation(name: "Frankfurt", coordinate: CLLocationCoordinate2D(latitude: 50.1109, longitude: 8.6821)),
        CityLocation(name: "Amsterdam", coordinate: CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041)),
        CityLocation(name: "Paris", coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)),
        CityLocation(name: "Tokyo", coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)),
        CityLocation(name: "Singapore", coordinate: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198)),
        CityLocation(name: "Hong Kong", coordinate: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)),
        CityLocation(name: "Taipei", coordinate: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)),
        CityLocation(name: "Seoul", coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)),
        CityLocation(name: "Sydney", coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093))
    ]

    func simulatedCoordinate(for key: String) -> CLLocationCoordinate2D {
        let hash = abs(key.hashValue)
        let city = globalHubs[hash % globalHubs.count]

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

    func generateColor(for string: String) -> Color {
        let palette: [Color] = [
            .seriesDown, .seriesUp, .statusGood, .statusWarn,
            .purple, .pink, .teal, .indigo
        ]
        return palette[abs(string.hashValue) % palette.count]
    }
}

// MARK: - Map

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

        for conn in connections {
            let polyline = MKGeodesicPolyline(
                coordinates: [localLocation, conn.coordinate],
                count: 2
            )
            mapView.addOverlay(polyline)

            let annotation = MKPointAnnotation()
            annotation.coordinate = conn.coordinate
            annotation.title = conn.host
            mapView.addAnnotation(annotation)
        }

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

            let config = MKStandardMapConfiguration(elevationStyle: .realistic)
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            config.emphasisStyle = .muted
            mapView.preferredConfiguration = config

            mapView.isZoomEnabled = true
            mapView.isScrollEnabled = true
            mapView.isPitchEnabled = true
            mapView.isRotateEnabled = true

            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47),
                fromDistance: 40_000_000,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = NSColor(Color.seriesDown).withAlphaComponent(0.55)
                renderer.lineWidth = 1.25
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
            marker?.annotation = annotation

            if annotation.title == "Me" {
                marker?.glyphImage = NSImage(systemSymbolName: "macbook", accessibilityDescription: nil)
                marker?.markerTintColor = .controlAccentColor
            } else {
                marker?.glyphImage = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
                marker?.markerTintColor = .secondaryLabelColor
            }

            marker?.displayPriority = .required
            marker?.subtitleVisibility = .hidden
            marker?.titleVisibility = .hidden
            return marker
        }
    }
}
