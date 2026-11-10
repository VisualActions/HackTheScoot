import SwiftUI
import MapKit
import CoreLocation

/// v5.0 opt-in GPS route for each ride. Off unless the rider turns it on; uses location
/// only "while using the app" (no background location), and the route stays on this phone.
final class RouteRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = RouteRecorder()
    static let enabledKey = "route.enabled"
    static let maxPoints = 20000

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: RouteRecorder.enabledKey) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: RouteRecorder.enabledKey)
            if enabled { requestPermission() }
        }
    }
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var recording = false
    @Published private(set) var lastError: String?
    private(set) var points: [Trip.RoutePoint] = []
    private var start = Date()
    private var manager: CLLocationManager?

    private func lm() -> CLLocationManager {
        if let m = manager { return m }
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
        m.distanceFilter = 5
        m.activityType = .otherNavigation
        manager = m
        authorization = m.authorizationStatus
        return m
    }

    var authorized: Bool { return authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    func requestPermission() {
        let m = lm()
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() }
    }

    /// Starts with a real (not simulated) trip, when the rider turned routes on.
    func begin(at t: Date) {
        guard enabled else { return }
        let m = lm()
        guard authorized else { requestPermission(); return }
        points = []
        start = t
        recording = true
        m.startUpdatingLocation()
    }

    /// Ends the route; nil when there was nothing worth keeping.
    func end() -> [Trip.RoutePoint]? {
        guard recording else { return nil }
        recording = false
        manager?.stopUpdatingLocation()
        let out = points
        points = []
        return out.count >= 2 ? out : nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recording else { return }
        for loc in locations where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 50 {
            let p = Trip.RoutePoint(t: max(0, loc.timestamp.timeIntervalSince(start)), lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
            if points.count < RouteRecorder.maxPoints, RouteMath.shouldKeep(p, after: points.last) { points.append(p) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }
}

/// A ride's route on a map (MKMapView, so it works on iOS 16).
struct RouteMapView: UIViewRepresentable {
    let route: [Trip.RoutePoint]
    var color: UIColor = .systemBlue

    func makeCoordinator() -> Coordinator { Coordinator(color: color) }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.isRotateEnabled = false
        m.showsCompass = false
        m.isAccessibilityElement = true
        m.accessibilityLabel = "Map of this ride's route"
        update(m)
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) { update(m) }

    private func update(_ m: MKMapView) {
        m.removeOverlays(m.overlays)
        m.removeAnnotations(m.annotations)
        let pts = route.filter(RouteMath.isValid).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard pts.count >= 2 else { return }
        let line = MKPolyline(coordinates: pts, count: pts.count)
        m.addOverlay(line)
        let s = MKPointAnnotation(); s.coordinate = pts[0]; s.title = "Start"
        let e = MKPointAnnotation(); e.coordinate = pts[pts.count - 1]; e.title = "End"
        m.addAnnotations([s, e])
        m.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let color: UIColor
        init(color: UIColor) { self.color = color }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let l = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: l)
            r.strokeColor = color
            r.lineWidth = 4
            return r
        }
    }
}

/// The route section in a ride's detail screen.
struct TripRouteSection: View {
    let trip: Trip
    let mph: Bool
    @EnvironmentObject var themes: ThemeStore

    var body: some View {
        if let r = trip.route, r.count >= 2 {
            Section(header: Text("Route"), footer: Text("GPS route, saved on this phone only. GPS length: \(UnitPref.distance(RouteMath.lengthKm(r), mph: mph)).")) {
                RouteMapView(route: r, color: UIColor(themes.accent))
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
            }
        } else {
            Section(footer: Text(RouteRecorder.shared.enabled ? "No GPS route for this ride (location was off, or the ride was simulated)." : "Turn on GPS routes in More > App settings to see rides on a map.")) {
                Label("No route", systemImage: "map").foregroundColor(.secondary)
            }
        }
    }
}

/// The opt-in switch (App settings).
struct RouteSettingsSection: View {
    @ObservedObject var rec = RouteRecorder.shared
    var body: some View {
        Section(header: Text("GPS routes"), footer: Text("Off by default. When on, each real ride saves its GPS route so you can see it on a map. Location is used only while HackTheScoot is open (not in the background) and never leaves this phone unless you export a ride.")) {
            Toggle(isOn: $rec.enabled) { Label("Record GPS routes on rides", systemImage: "map") }
            if rec.enabled && (rec.authorization == .denied || rec.authorization == .restricted) {
                Text("Location is off for HackTheScoot in iOS Settings, so no routes are saved.").font(.footnote).foregroundColor(.orange)
            }
        }
    }
}
