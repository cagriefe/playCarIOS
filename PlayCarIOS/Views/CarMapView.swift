import SwiftUI
import MapKit

/// Harita takip modu (Apple Haritalar konum butonu döngüsü):
/// none → follow (kuzey sabit) → heading (yöne dönen) → follow …
enum MapFollowMode: Equatable {
    case none
    case follow
    case heading
}

// MARK: - MKMapView wrapper (trafik destekli)

/// Apple Haritalar davranışı:
/// - Normalde MapKit'in kendi takip modları (follow / followWithHeading).
/// - Navigasyonda sürüş kamerası: GPS gidiş yönüne (course) göre döner —
///   araç içinde pusula metal yüzünden sapar — konum noktası ekranın alt
///   kısmında durur, zoom manevra mesafesine göre kendiliğinden ayarlanır.
/// - Kaydırma takibi bırakır, iki parmakla zoom takibi bozmaz.
/// - Harita hep 2D (tepeden); döndürme serbest, mekana dokunma ve uzun basıp işaretleme var.
struct CarMapView: UIViewRepresentable {
    var userLocation: CLLocationCoordinate2D?
    @Binding var selectedPlace: MKMapItem?
    @Binding var cameraTarget: CLLocationCoordinate2D?
    var showTraffic: Bool
    @Binding var followMode: MapFollowMode
    var favorites: [FavoritePlace]
    var route: MKRoute?
    /// Önizlemede seçilmemiş alternatif rotalar: gri çizilir, dokununca seçilir.
    var alternateRoutes: [MKRoute] = []
    @Binding var overviewRoute: MKRoute?
    /// İlk konumda bir kez uygulanan 2D açılış kamerası.
    @Binding var initialCenter: CLLocationCoordinate2D?
    /// true = açık (gündüz) harita, false = koyu (gece) harita.
    var mapStyleLight: Bool
    @Binding var tapTick: Int
    @Binding var panTick: Int
    /// Haritanın kuzeye göre dönüklüğü (derece) — pusula butonu için.
    @Binding var mapHeading: Double
    /// Her artışta harita kuzeye döner.
    var resetNorthTick: Int
    var isNavigating: Bool
    /// Navigasyonda manevraya göre kamera yüksekliği (m). 0 = pasif.
    var navAltitude: Double
    /// Rota önizlemesinde soldaki ray + çentik payı.
    var overviewLeftPadding: CGFloat
    var onPickPlace: (MKMapItem, String) -> Void
    var onDropPin: (CLLocationCoordinate2D) -> Void
    var onSelectRoute: (MKRoute) -> Void = { _ in }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        let c = context.coordinator
        c.parent = self
        map.delegate = c
        map.preferredConfiguration = Self.configuration(traffic: showTraffic)
        c.lastTraffic = showTraffic
        map.showsUserLocation = true
        map.showsCompass = false // kendi pusula butonumuz ray altında
        map.showsScale = true
        // Harita her zaman 2D (tepeden): yatırma kapalı, döndürme açık.
        map.isPitchEnabled = false
        map.isRotateEnabled = true
        map.selectableMapFeatures = [.pointsOfInterest]
        map.overrideUserInterfaceStyle = mapStyleLight ? .light : .dark
        map.setUserTrackingMode(Self.trackingMode(for: followMode), animated: false)
        c.lastResetNorthTick = resetNorthTick

        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let multiPan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handleMultiTouch(_:)))
        multiPan.minimumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: c, action: #selector(Coordinator.handleRotate(_:)))
        let longPress = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        for g in [tap, pan, multiPan, pinch, rotate, longPress] as [UIGestureRecognizer] {
            // Sadece gözlemci: MKMapView'ın kendi hareketlerini engellemesin.
            g.cancelsTouchesInView = false
            g.delegate = c
            map.addGestureRecognizer(g)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        // Bu fonksiyon içindeki kamera/mod değişiklikleri programatik;
        // delegate bunları "kullanıcı takibi bıraktı" diye yorumlamasın.
        c.isUpdating = true
        defer { c.isUpdating = false }

        if c.lastTraffic != showTraffic {
            c.lastTraffic = showTraffic
            map.preferredConfiguration = Self.configuration(traffic: showTraffic)
        }
        let style: UIUserInterfaceStyle = mapStyleLight ? .light : .dark
        if map.overrideUserInterfaceStyle != style { map.overrideUserInterfaceStyle = style }

        updateAnnotations(map, c)
        updateOverlays(map, c)

        // Tek seferlik kamera komutları
        if let overview = overviewRoute {
            // Alternatifler varsa hepsi kadraja girsin.
            var rect = alternateRoutes.reduce(overview.polyline.boundingMapRect) {
                $0.union($1.polyline.boundingMapRect)
            }
            let w = rect.size.width, h = rect.size.height
            rect = rect.insetBy(dx: -w * 0.15, dy: -h * 0.15)
            map.setUserTrackingMode(.none, animated: false)
            // Üstte arama/rota kartı, solda ray var: rota onların altında kalmasın.
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 150, left: overviewLeftPadding, bottom: 30, right: 30), animated: true)
            DispatchQueue.main.async { overviewRoute = nil }
        } else if let target = cameraTarget {
            // Seçilen yere git: makul bir yakınlıkta ortala.
            map.setUserTrackingMode(.none, animated: false)
            let cam = map.camera
            let altitude = (300...4000).contains(cam.altitude) ? cam.altitude : 1200
            let newCam = MKMapCamera(lookingAtCenter: target, fromDistance: altitude, pitch: 0, heading: cam.heading)
            map.setCamera(newCam, animated: true)
            DispatchQueue.main.async { cameraTarget = nil }
        } else if let first = initialCenter {
            // Açılış: 2D tepeden, sokak seviyesi yakınlık
            map.setCamera(MKMapCamera(lookingAtCenter: first, fromDistance: 1500, pitch: 0, heading: 0), animated: false)
            DispatchQueue.main.async { initialCenter = nil }
        }

        if resetNorthTick != c.lastResetNorthTick {
            c.lastResetNorthTick = resetNorthTick
            if followMode == .heading && !isNavigating {
                followMode = .follow
            }
            let cam = map.camera
            cam.heading = 0
            map.setCamera(cam, animated: true)
        }

        // Takip
        let navFollow = isNavigating && followMode != .none
        if navFollow {
            if map.userTrackingMode != .none { map.setUserTrackingMode(.none, animated: false) }
            if !c.navFollowing {
                // Sürüş kamerasına ilk geçiş: hemen uygula.
                c.navFollowing = true
                c.applyNavCamera(map, location: map.userLocation.location, duration: 0.6)
            } else if abs(c.lastNavAltitude - navAltitude) > 1 {
                // Manevra mesafesi bandı değişti: zoom'u yumuşakça güncelle.
                c.applyNavCamera(map, location: map.userLocation.location, duration: 1.0)
            }
        } else {
            c.navFollowing = false
            c.navFollowingHasHeading = false
            let desired = Self.trackingMode(for: followMode)
            if map.userTrackingMode != desired {
                map.setUserTrackingMode(desired, animated: true)
            }
        }
    }

    private func updateAnnotations(_ map: MKMapView, _ c: Coordinator) {
        // Seçili yer + favori pin'leri — SADECE değişince yeniden kur.
        // Rota varken seçili yer iğnesi yerine varış bayrağı gösterilir.
        let shownPlace = route == nil ? selectedPlace : nil
        let selectedKey: String? = shownPlace.map {
            "\($0.placemark.coordinate.latitude),\($0.placemark.coordinate.longitude),\($0.name ?? "")"
        }
        let favKey = favorites.map { $0.id.uuidString + ($0.kind?.rawValue ?? "") }.joined(separator: "|")
        guard selectedKey != c.lastSelectedKey || favKey != c.lastFavKey else { return }
        c.lastSelectedKey = selectedKey
        c.lastFavKey = favKey
        map.removeAnnotations(map.annotations.filter {
            $0 is MKPointAnnotation
        })
        for fav in favorites {
            let ann = FavoriteAnnotation()
            ann.kind = fav.kind
            ann.coordinate = fav.coordinate
            ann.title = fav.name
            ann.subtitle = fav.address
            map.addAnnotation(ann)
        }
        if let item = shownPlace {
            // Haritadaki mekan seçimini kaldır, yerine kırmızı iğne koy.
            for sel in map.selectedAnnotations where sel is MKMapFeatureAnnotation {
                map.deselectAnnotation(sel, animated: false)
            }
            let isFavorite = favorites.contains {
                abs($0.latitude - item.placemark.coordinate.latitude) < 1e-4 &&
                abs($0.longitude - item.placemark.coordinate.longitude) < 1e-4
            }
            if !isFavorite {
                let ann = MKPointAnnotation()
                ann.coordinate = item.placemark.coordinate
                ann.title = item.name
                map.addAnnotation(ann)
                map.selectAnnotation(ann, animated: true)
            }
        }
    }

    private func updateOverlays(_ map: MKMapView, _ c: Coordinator) {
        // Rota çizgisi: beyaz zemin + mavi hat (yüksek kontrast) — SADECE rota değişince.
        // Trafik açıkken rota yarı saydam çizilir: trafik renkleri içinden görünür.
        let routeID = route.map { ObjectIdentifier($0.polyline) }
        let alternateIDs = alternateRoutes.map { ObjectIdentifier($0.polyline) }
        guard routeID != c.lastRouteID || showTraffic != c.lastRouteTraffic || alternateIDs != c.lastAlternateIDs else { return }
        c.lastRouteID = routeID
        c.lastRouteTraffic = showTraffic
        c.lastAlternateIDs = alternateIDs
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { $0 is DestinationAnnotation })
        // Alternatifler önce eklenir: seçili rota hep üstte kalır.
        c.alternateLines = alternateRoutes.map { alt in
            let line = AlternateRoutePolyline(points: alt.polyline.points(), count: alt.polyline.pointCount)
            map.addOverlay(line, level: .aboveRoads)
            return (line, alt)
        }
        if let route {
            if showTraffic {
                let faded = RouteTrafficPolyline(points: route.polyline.points(), count: route.polyline.pointCount)
                map.addOverlay(faded, level: .aboveRoads)
            } else {
                let casing = RouteCasingPolyline(points: route.polyline.points(), count: route.polyline.pointCount)
                map.addOverlay(casing, level: .aboveRoads)
                map.addOverlay(route.polyline, level: .aboveRoads)
            }
            // Varış bayrağı: rota boyunca hedef her zaman görünür.
            let n = route.polyline.pointCount
            if n > 0 {
                map.addAnnotation(DestinationAnnotation(coordinate: route.polyline.points()[n - 1].coordinate))
            }
        }
    }

    private static func configuration(traffic: Bool) -> MKMapConfiguration {
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
        config.showsTraffic = traffic
        return config
    }

    private static func trackingMode(for mode: MapFollowMode) -> MKUserTrackingMode {
        switch mode {
        case .none: return .none
        case .follow: return .follow
        case .heading: return .followWithHeading
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: CarMapView
        var isUpdating = false
        var lastTraffic = true
        var lastSelectedKey: String?
        var lastFavKey = ""
        var lastRouteID: ObjectIdentifier?
        var lastRouteTraffic = false
        var lastAlternateIDs: [ObjectIdentifier] = []
        var alternateLines: [(line: AlternateRoutePolyline, route: MKRoute)] = []
        var lastResetNorthTick = 0
        var navFollowing = false
        var lastNavAltitude: Double = 0
        var lastNavHeading: CLLocationDirection = 0
        /// Kullanıcı iki parmakla zoom yaptıysa bir süre otomatik zoom'a karışma.
        var userZoomUntil = Date.distantPast
        /// Son kullanıcı hareketi: takip modu değişikliği bundan kaynaklanıyorsa senkronla.
        var lastUserGesture = Date.distantPast

        init(parent: CarMapView) {
            self.parent = parent
        }

        // MARK: Hareketler

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView else { return }
            // Pin / mekan / konum noktasına dokunuşu kontrol göster-gizle sayma.
            var hit = map.hitTest(g.location(in: map), with: nil)
            while let v = hit, v !== map {
                if v is MKAnnotationView { return }
                hit = v.superview
            }
            // Gri alternatif rotaya dokunuldu: o rotayı seç.
            if let route = alternateRoute(near: g.location(in: map), in: map) {
                parent.onSelectRoute(route)
                return
            }
            parent.tapTick += 1
        }

        /// Dokunulan noktaya ~24 pt'den yakın alternatif rota (en yakını).
        private func alternateRoute(near point: CGPoint, in map: MKMapView) -> MKRoute? {
            var best: (route: MKRoute, distance: CGFloat)?
            for (line, route) in alternateLines {
                let d = Self.distance(from: point, to: line, in: map)
                if d < 24, d < (best?.distance ?? .greatestFiniteMagnitude) {
                    best = (route, d)
                }
            }
            return best?.route
        }

        private static func distance(from p: CGPoint, to line: MKPolyline, in map: MKMapView) -> CGFloat {
            let pts = line.points()
            var best = CGFloat.greatestFiniteMagnitude
            var previous: CGPoint?
            for i in 0..<line.pointCount {
                let v = map.convert(pts[i].coordinate, toPointTo: map)
                if let a = previous {
                    let dx = v.x - a.x, dy = v.y - a.y
                    let len2 = dx * dx + dy * dy
                    var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
                    t = min(max(t, 0), 1)
                    best = min(best, hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)))
                }
                previous = v
            }
            return best
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard g.state == .began else { return }
            lastUserGesture = Date()
            if parent.followMode != .none { parent.followMode = .none }
            parent.panTick += 1
        }

        @objc func handleMultiTouch(_ g: UIPanGestureRecognizer) {
            if g.state == .began || g.state == .changed { lastUserGesture = Date() }
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .began || g.state == .changed else { return }
            lastUserGesture = Date()
            // Navigasyonda zoom takibi bozmaz; 10 sn kullanıcının zoom'u korunur.
            userZoomUntil = Date().addingTimeInterval(10)
        }

        @objc func handleRotate(_ g: UIRotationGestureRecognizer) {
            guard g.state == .began else { return }
            lastUserGesture = Date()
            if parent.isNavigating, parent.followMode != .none {
                parent.followMode = .none
            }
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            parent.onDropPin(coord)
        }

        // MARK: Sürüş kamerası

        func applyNavCamera(_ map: MKMapView, location: CLLocation?, duration: TimeInterval) {
            guard let loc = location, map.bounds.height > 0 else { return }
            // Yön: hareket halindeyken GPS gidiş yönü; dururken son yön korunur.
            if loc.course >= 0, loc.speed > 1.5 {
                lastNavHeading = loc.course
            } else if !navFollowingHasHeading {
                lastNavHeading = map.camera.heading
            }
            navFollowingHasHeading = true
            let distance: Double
            if Date() < userZoomUntil {
                distance = map.camera.centerCoordinateDistance
            } else {
                distance = parent.navAltitude > 0 ? parent.navAltitude : 800
                lastNavAltitude = parent.navAltitude
            }
            // Konum noktası ekranın alt-orta kısmında dursun (≈ %70):
            // ekranda istenen kaydırmayı GERÇEK ölçekten metreye çevir.
            let screenOffset = Double(map.bounds.height) * 0.2
            let ahead = Self.metersPerPoint(map, atDistance: distance) * screenOffset
            let center = Self.coordinate(loc.coordinate, movedBy: ahead, bearing: lastNavHeading)
            let cam = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: lastNavHeading)
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]
            ) {
                map.camera = cam
            }
        }

        /// Hedef kamera mesafesinde ekranın bir noktasının kaç metre olduğu.
        /// Mevcut görünümün ortasından ölçülür, mesafe oranıyla ölçeklenir.
        private static func metersPerPoint(_ map: MKMapView, atDistance target: Double) -> Double {
            let mid = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
            let a = map.convert(CGPoint(x: mid.x - 50, y: mid.y), toCoordinateFrom: map)
            let b = map.convert(CGPoint(x: mid.x + 50, y: mid.y), toCoordinateFrom: map)
            let current = MKMapPoint(a).distance(to: MKMapPoint(b)) / 100
            let currentDistance = map.camera.centerCoordinateDistance
            guard current.isFinite, current > 0, currentDistance > 0 else { return 0 }
            return current * target / currentDistance
        }

        var navFollowingHasHeading = false

        private static func coordinate(_ c: CLLocationCoordinate2D, movedBy meters: Double, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
            let r = 6_371_000.0
            let d = meters / r
            let b = bearing * .pi / 180
            let lat1 = c.latitude * .pi / 180
            let lon1 = c.longitude * .pi / 180
            let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
            let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
            return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard navFollowing else {
                navFollowingHasHeading = false
                return
            }
            applyNavCamera(mapView, location: userLocation.location, duration: 1.0)
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            // Sadece kullanıcı hareketinden kaynaklanan değişiklikleri yansıt
            // (kaydırma → takip biter, döndürme → yöne göre dönme biter).
            guard !isUpdating, !parent.isNavigating,
                  Date().timeIntervalSince(lastUserGesture) < 1.5 else { return }
            let newMode: MapFollowMode
            switch mode {
            case .follow: newMode = .follow
            case .followWithHeading: newMode = .heading
            default: newMode = .none
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.followMode != newMode else { return }
                self.parent.followMode = newMode
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            #if DEBUG
            if parent.isNavigating {
                let pt = mapView.convert(mapView.userLocation.coordinate, toPointTo: mapView)
                print(String(format: "PCDBG CAM follow=%@ navFollowing=%d puck=(%.2f, %.2f) dist=%.0f pitch=%.0f heading=%.0f mode=%d",
                             "\(parent.followMode)", navFollowing ? 1 : 0,
                             pt.x / max(mapView.bounds.width, 1), pt.y / max(mapView.bounds.height, 1),
                             mapView.camera.centerCoordinateDistance, mapView.camera.pitch,
                             mapView.camera.heading, mapView.userTrackingMode.rawValue))
            }
            #endif
            let heading = mapView.camera.heading
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.mapHeading - heading) > 1 else { return }
                self.parent.mapHeading = heading
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            // Haritadaki bir mekana (POI) dokunuldu: detayını çözüp seçili yer yap.
            guard let feature = annotation as? MKMapFeatureAnnotation else { return }
            MKMapItemRequest(mapFeatureAnnotation: feature).getMapItem { [weak self] item, _ in
                guard let self, let item else { return }
                let subtitle = MapPlaceFormat.address(of: item.placemark)
                self.parent.onPickPlace(item, subtitle)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation || annotation is MKMapFeatureAnnotation { return nil }
            if annotation is DestinationAnnotation {
                let id = "destPin"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.glyphImage = UIImage(systemName: "flag.checkered")
                v.markerTintColor = .systemRed
                v.displayPriority = .required
                v.canShowCallout = false
                return v
            }
            if let fav = annotation as? FavoriteAnnotation {
                let id = "favPin"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.glyphImage = UIImage(systemName: FavoritePlace.icon(for: fav.kind))
                v.markerTintColor = FavoritePlace.uiColor(for: fav.kind)
                v.canShowCallout = true
                v.displayPriority = .required
                return v
            }
            return nil // seçili yer: varsayılan kırmızı pin + callout
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? RouteTrafficPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.55)
                r.lineWidth = 6
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            if overlay is RouteCasingPolyline, let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .white
                r.lineWidth = 11
                r.lineCap = .round
                r.lineJoin = .round
                r.alpha = 0.9
                return r
            }
            if overlay is AlternateRoutePolyline, let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.systemGray.withAlphaComponent(0.85)
                r.lineWidth = 7
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemBlue
                r.lineWidth = 7
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

/// Adres metni: "Sokak No, İlçe, İl" (boş parçalar atlanır).
enum MapPlaceFormat {
    static func address(of pm: CLPlacemark) -> String {
        let street = [pm.thoroughfare, pm.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street, pm.subLocality ?? pm.locality, pm.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }.joined(separator: ", ")
    }
}

/// Rota beyaz zemini: mavi hattın altında daha kalın beyaz çizgi.
final class RouteCasingPolyline: MKPolyline {}

/// Trafik açıkken rota: ince, yarı saydam mavi; alttaki trafik rengi içinden görünür.
final class RouteTrafficPolyline: MKPolyline {}

/// Önizlemede seçilmemiş alternatif rota: gri.
final class AlternateRoutePolyline: MKPolyline {}

/// Rota varış noktası (seçili yer / favori pin'lerinden bağımsız).
final class DestinationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// Favori pin'lerini varsayılan pinden ayırmak için alt sınıf.
final class FavoriteAnnotation: MKPointAnnotation {
    var kind: PlaceKind?
}
