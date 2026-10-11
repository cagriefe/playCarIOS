import SwiftUI
import MapKit

/// Harita paneli: sol %60.
/// DÜZELTME NOTU: SwiftUI `Map` (iOS 17) trafik katmanı sunmaz.
/// Bu yüzden trafik + 2D/3D + takip için MKMapView UIViewRepresentable kullanıldı.
/// showsTraffic = true gerçekten çalışır.
struct MapPanelView: View {
    @ObservedObject var locationManager: LocationManager
    @StateObject private var searchService = SearchService()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var nav = NavigationStore()
    @State private var cameraTarget: CLLocationCoordinate2D?
    @State private var selectedPlace: MKMapItem?
    @State private var selectedSubtitle = ""
    @State private var is3D = false
    @State private var showTraffic = true
    @State private var followUser = true
    @State private var showFavorites = false
    @State private var overviewRoute: MKRoute?

    var body: some View {
        ZStack(alignment: .top) {
            CarMapView(
                userLocation: locationManager.lastLocation?.coordinate,
                selectedPlace: $selectedPlace,
                cameraTarget: $cameraTarget,
                is3D: is3D,
                showTraffic: showTraffic,
                followUser: followUser,
                favorites: favorites.favorites,
                route: nav.route,
                overviewRoute: $overviewRoute
            )
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    SearchBarView(searchService: searchService) { completion in
                        searchService.resolve(completion) { item in
                            guard let item else { return }
                            nav.stop()
                            overviewRoute = nil
                            selectedPlace = item
                            selectedSubtitle = completion.subtitle
                            cameraTarget = item.placemark.coordinate
                            followUser = false
                        }
                    } onSave: { completion in
                        searchService.resolve(completion) { item in
                            guard let item else { return }
                            favorites.add(
                                name: item.name ?? completion.title,
                                address: completion.subtitle,
                                coordinate: item.placemark.coordinate
                            )
                        }
                    }

                    if locationManager.authState != .authorized {
                        LocationPermissionBanner(
                            state: locationManager.authState,
                            onRequest: { locationManager.requestPermission() }
                        )
                    }

                    navBanner
                }
                .frame(maxWidth: 340)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 46) // üst durum çubuğunun altında

            // Sol ikon rayı (CarPlay sidebar): dikey ortalı yüzen hap
            HStack {
                VStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        railButton(icon: "location.fill", active: followUser, action: recenter)
                        railButton(icon: is3D ? "view.3d" : "view.2d", active: is3D) { is3D.toggle() }
                        railButton(icon: "car.fill", active: showTraffic) { showTraffic.toggle() }
                        railButton(icon: "star.fill", active: false) { showFavorites = true }
                    }
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 52)
            .frame(maxHeight: .infinity)

            // Seçili yer kartı (sol altta, sağ kartların önünden çekik)
            HStack(alignment: .bottom) {
                if let item = selectedPlace {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name ?? "Seçili konum")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(selectedSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button {
                            startPreview(for: item)
                        } label: {
                            Image(systemName: "car.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                        }
                        Button {
                            favorites.add(
                                name: item.name ?? "Seçili konum",
                                address: selectedSubtitle,
                                coordinate: item.placemark.coordinate
                            )
                        } label: {
                            Image(systemName: favorites.contains(coordinate: item.placemark.coordinate)
                                  ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(.yellow)
                                .frame(width: 44, height: 44)
                        }
                        Button { selectedPlace = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 330)
                } else {
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 116)
            .padding(.trailing, 324)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startTracking()
        }
        .onChange(of: locationManager.lastLocation?.coordinate.latitude) { _, _ in
            guard let coord = locationManager.lastLocation?.coordinate else { return }
            searchService.updateRegion(around: coord)
            if let loc = locationManager.lastLocation {
                nav.updateLocation(loc)
            }
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheetView(
                favorites: favorites,
                onGo: { place in
                    showFavorites = false
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                    item.name = place.name
                    nav.stop()
                    overviewRoute = nil
                    selectedPlace = item
                    selectedSubtitle = place.address
                    followUser = false
                    if locationManager.lastLocation != nil {
                        startPreview(for: item)
                    } else {
                        cameraTarget = place.coordinate
                    }
                }
            )
        }
        .onChange(of: nav.phase) { _, phase in
            if phase == .preview {
                overviewRoute = nav.route
            }
        }
    }

    private func startPreview(for item: MKMapItem) {
        guard let loc = locationManager.lastLocation else {
            nav.lastError = "Önce konum bekleniyor…"
            return
        }
        nav.previewRoute(to: item, from: loc)
    }

    private func recenter() {
        followUser = true
        selectedPlace = nil
        if let coord = locationManager.lastLocation?.coordinate {
            cameraTarget = coord
        }
    }

    /// Sol ray butonu: CarPlay sidebar tarzı yuvarlak dokunmatik hedef.
    private func railButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(active ? Color.accentColor : Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
    }

    /// Navigasyon durum kartları (arama çubuğunun altında).
    @ViewBuilder
    private var navBanner: some View {
        switch nav.phase {
        case .idle:
            if let err = nav.lastError {
                Button { nav.lastError = nil } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(err).font(.caption).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        case .calculating:
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("Rota hesaplanıyor…").font(.caption).foregroundStyle(.primary)
                Spacer()
                Button("Vazgeç") { nav.stop() }.font(.caption.bold())
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .preview:
            HStack(spacing: 8) {
                Image(systemName: "car.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 0) {
                    Text(nav.destinationName).font(.subheadline.bold()).lineLimit(1)
                    Text("\(NavFormat.distance(nav.distanceRemaining)) • Varış \(nav.eta.map(NavFormat.time) ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Başla") {
                    followUser = true
                    nav.start()
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                Button("Kapat") { nav.stop(); overviewRoute = nil }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .navigating:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(nav.nextInstruction.isEmpty ? "Devam edin" : nav.nextInstruction)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(NavFormat.distance(nav.nextDistance))
                        .font(.headline.bold())
                        .foregroundStyle(.green)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text("Kalan \(NavFormat.distance(nav.distanceRemaining)) • Varış \(nav.eta.map(NavFormat.time) ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        nav.muted.toggle()
                    } label: {
                        Image(systemName: nav.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.caption)
                            .frame(width: 36, height: 28)
                    }
                    Button("Bitir") { nav.stop(); overviewRoute = nil }
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .arrived:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Vardınız: \(nav.destinationName)")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Button("Kapat") { nav.stop(); overviewRoute = nil }
                    .font(.caption.bold())
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - MKMapView wrapper (trafik destekli)

struct CarMapView: UIViewRepresentable {
    var userLocation: CLLocationCoordinate2D?
    @Binding var selectedPlace: MKMapItem?
    @Binding var cameraTarget: CLLocationCoordinate2D?
    var is3D: Bool
    var showTraffic: Bool
    var followUser: Bool
    var favorites: [FavoritePlace]
    var route: MKRoute?
    @Binding var overviewRoute: MKRoute?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false // üst bardaki kendi pusulamız var; çakışmasın
        map.showsScale = true
        map.showsTraffic = showTraffic
        map.userTrackingMode = .followWithHeading
        map.mapType = .standard
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.showsTraffic = showTraffic

        if followUser {
            if map.userTrackingMode != .followWithHeading {
                map.setUserTrackingMode(.followWithHeading, animated: true)
            }
        } else {
            if map.userTrackingMode != .none {
                map.setUserTrackingMode(.none, animated: true)
            }
        }

        // Seçili yer + favori pin'leri
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        if let item = selectedPlace {
            let ann = MKPointAnnotation()
            ann.coordinate = item.placemark.coordinate
            ann.title = item.name
            map.addAnnotation(ann)
        }
        for fav in favorites {
            let ann = FavoriteAnnotation()
            ann.coordinate = fav.coordinate
            ann.title = fav.name
            ann.subtitle = fav.address
            map.addAnnotation(ann)
        }

        // Rota çizgisi
        map.removeOverlays(map.overlays)
        if let route {
            map.addOverlay(route.polyline, level: .aboveRoads)
        }

        // Önizlemede tüm rotayı kadraja al (tek seferlik)
        if let overview = overviewRoute {
            var rect = overview.polyline.boundingMapRect
            let w = rect.size.width, h = rect.size.height
            rect = rect.insetBy(dx: -w * 0.25, dy: -h * 0.25)
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 20, bottom: 20, right: 20), animated: true)
            DispatchQueue.main.async {
                overviewRoute = nil
            }
        }

        // Kamera hedefi
        if let target = cameraTarget {
            let camera: MKMapCamera
            if is3D {
                camera = MKMapCamera(
                    lookingAtCenter: target,
                    fromDistance: 800,
                    pitch: 60,
                    heading: 0
                )
            } else {
                camera = MKMapCamera(
                    lookingAtCenter: target,
                    fromDistance: 2000,
                    pitch: 0,
                    heading: 0
                )
            }
            map.setCamera(camera, animated: true)
            DispatchQueue.main.async {
                // Tek seferlik uygula, sürekli zıplamasın
                cameraTarget = nil
            }
        } else if is3D != context.coordinator.last3D {
            // Sadece 2D/3D değişiminde pitch güncelle
            var cam = map.camera
            cam.pitch = is3D ? 60 : 0
            map.setCamera(cam, animated: true)
            context.coordinator.last3D = is3D
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var last3D = false

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is FavoriteAnnotation {
                let id = "favPin"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.glyphImage = UIImage(systemName: "star.fill")
                v.markerTintColor = .systemYellow
                v.canShowCallout = true
                return v
            }
            return nil // seçili yer: varsayılan kırmızı pin + callout
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemBlue
                r.lineWidth = 6
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Arama çubuğu

/// Favori pin'lerini varsayılan pinden ayırmak için alt sınıf.
final class FavoriteAnnotation: MKPointAnnotation {}

struct SearchBarView: View {
    @ObservedObject var searchService: SearchService
    var onSelect: (MKLocalSearchCompletion) -> Void
    var onSave: (MKLocalSearchCompletion) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Adres veya mekan ara (örn. Kadıköy)", text: $searchService.query)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit { focused = false }
                    if searchService.isSearching {
                        ProgressView().scaleEffect(0.8)
                    } else if !searchService.query.isEmpty {
                        Button { searchService.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Klavye açıkken haritada boşluğa dokunmak klavyeyi kapatmaz
                // (MKMapView dokunmaları yutar). Standart çıkış: Vazgeç.
                if focused {
                    Button("Vazgeç") {
                        searchService.query = ""
                        focused = false
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if focused && !searchService.completions.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.completions, id: \.self) { c in
                            HStack(spacing: 0) {
                                Button {
                                    focused = false
                                    onSelect(c)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).font(.subheadline).foregroundStyle(.primary)
                                        Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                }
                                // Satır içi favoriye ekle (Maps'teki gibi)
                                Button { onSave(c) } label: {
                                    Image(systemName: "star")
                                        .font(.body)
                                        .foregroundStyle(.yellow)
                                        .frame(width: 44, height: 44)
                                }
                            }
                            if c != searchService.completions.last {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - İzin banner

/// Favoriler listesi: dokun → oraya git, kaydır → sil.
struct FavoritesSheetView: View {
    @ObservedObject var favorites: FavoritesStore
    var onGo: (FavoritePlace) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if favorites.favorites.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text("Henüz favori yok")
                            .font(.headline)
                        Text("Aramada satırdaki ★ ile veya seçili yer kartındaki ★ ile ekleyin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(favorites.favorites) { place in
                            Button { onGo(place) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(place.name)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(place.address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { favorites.remove(at: $0) }
                    }
                }
            }
            .navigationTitle("Favorilerim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct LocationPermissionBanner: View {
    var state: LocationManager.AuthState
    var onRequest: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "location.slash.fill").foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button("İzin Ver", action: onRequest)
                .font(.caption.bold())
            Button("Ayarlar") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var message: String {
        switch state {
        case .denied: return "Konum kapalı. Hız ve harita çalışmaz."
        case .restricted: return "Konum kısıtlı."
        case .notDetermined: return "Harita için konum izni gerekli."
        case .authorized: return ""
        }
    }
}
