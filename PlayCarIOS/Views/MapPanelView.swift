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
    @State private var initialCenter: CLLocationCoordinate2D?
    @State private var navStartCenter: CLLocationCoordinate2D?
    @State private var didInitialZoom = false
    @AppStorage("mapStyleLight") private var mapStyleLight = false
    /// Sürüş modu: 4 sn işlemsizlikte ray + arama gizlenir (temiz harita).
    /// Navigasyon kartı ve seçili yer kartı her zaman görünür (güvenlik).
    @State private var controlsVisible = true
    @State private var hideTimer: Timer?
    @State private var mapTapTick = 0
    @State private var mapPanTick = 0

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
                overviewRoute: $overviewRoute,
                initialCenter: $initialCenter,
                mapStyleLight: mapStyleLight,
                navStartCenter: $navStartCenter,
                tapTick: $mapTapTick,
                panTick: $mapPanTick
            )
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 8) {
                // Ray soldadır; sütun onun sağında ortalanır (çakışma yok)
                Spacer(minLength: 100)
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

                    // Turn-by-turn kartı: sol panelin üstünde, arama altında sabit
                    navBanner
                }
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)

            // Sol ikon rayı (CarPlay sidebar): dikey ortalı yüzen hap
            HStack {
                VStack {
                    Spacer(minLength: 76)
                    VStack(spacing: 5) {
                        railButton(icon: "location.fill", active: followUser, action: recenter)
                        railButton(icon: is3D ? "view.3d" : "view.2d", active: is3D) { is3D.toggle() }
                        railButton(icon: "car.fill", active: showTraffic) { showTraffic.toggle() }
                        railButton(icon: mapStyleLight ? "sun.max.fill" : "moon.fill", active: false) { mapStyleLight.toggle() }
                        railButton(icon: "star.fill", active: false) { showFavorites = true }
                    }
                    .padding(5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 36)
            .frame(maxHeight: .infinity)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)

            // Seçili yer kartı (sol altta; navigasyon sırasında banner var diye gizlenir)
            HStack(alignment: .bottom) {
                if let item = selectedPlace, nav.phase == .idle {
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
            .padding(.leading, 104)
            .padding(.trailing, 12)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startTracking()
            pokeControls()
        }
        .onDisappear {
            hideTimer?.invalidate()
        }
        .onChange(of: locationManager.lastLocation?.coordinate.latitude) { _, _ in
            guard let coord = locationManager.lastLocation?.coordinate else { return }
            searchService.updateRegion(around: coord)
            if !didInitialZoom {
                // Açılışta bir kez: 2D tepeden kamera
                didInitialZoom = true
                initialCenter = coord
            }
            if let loc = locationManager.lastLocation {
                nav.updateLocation(loc)
            }
        }
        .onChange(of: mapTapTick) {
            toggleControls()
        }
        .onChange(of: mapPanTick) {
            // Kullanıcı haritayı elle kaydırdı: takibi bırak, kontrolleri göster
            followUser = false
            pokeControls()
        }
        .onChange(of: searchService.query) {
            pokeControls()
        }
        .onChange(of: showFavorites) { _, shown in
            if shown {
                hideTimer?.invalidate()
                controlsVisible = true
            } else {
                pokeControls()
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
            if phase == .idle {
                // Navigasyon bitti: takibe dön
                followUser = true
            }
            pokeControls()
        }
    }

    /// Kontrolleri göster + 4 sn sonra otomatik gizle (temiz sürüş görünümü).
    /// @State atamaları non-mutating setter kullanır, escaping closure'dan çağrılabilir.
    private func pokeControls() {
        controlsVisible = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
        }
    }

    private func toggleControls() {
        hideTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.25)) { controlsVisible.toggle() }
        if controlsVisible { pokeControls() }
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
    /// Her dokunuş gizleme sayacını sıfırlar.
    private func railButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            pokeControls()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
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
                    if let coord = locationManager.lastLocation?.coordinate {
                        navStartCenter = coord
                    }
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
    /// İlk konumda bir kez uygulanan 2D açılış kamerası (zoom + pitch sabit).
    /// Sonrası merkez-kaydırma: zoom/pitch'e dokunulmaz.
    @Binding var initialCenter: CLLocationCoordinate2D?
    /// true = açık (gündüz) harita, false = koyu (gece) harita.
    /// Uygulama koyu temaya zorlu olduğu için harita varsayılanı
    /// sistemden değil buradan gelir.
    var mapStyleLight: Bool
    /// Navigasyon Başla'da bir kez uygulanan 2D yakın zoom (500 m, pitch 0).
    /// Sonrası normal takip: 2D + baş yönü, zoom kullanıcıda.
    @Binding var navStartCenter: CLLocationCoordinate2D?
    @Binding var tapTick: Int
    @Binding var panTick: Int

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false // üst bardaki kendi pusulamız var; çakışmasın
        map.showsScale = true
        map.showsTraffic = showTraffic
        map.userTrackingMode = .followWithHeading
        map.mapType = .standard
        map.overrideUserInterfaceStyle = mapStyleLight ? .light : .dark
        // Eğiklik kilidi: sadece 3D modunda parmakla yatırılabilir.
        // Böylece tüm zoom/pinch hareketleri 2D tepeden olur.
        map.isPitchEnabled = is3D
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = false
        map.addGestureRecognizer(pan)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.showsTraffic = showTraffic
        map.overrideUserInterfaceStyle = mapStyleLight ? .light : .dark
        map.isPitchEnabled = is3D

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

        // Rota çizgisi: beyaz zemin + mavi hat (yüksek kontrast)
        map.removeOverlays(map.overlays)
        if let route {
            let casing = RouteCasingPolyline(points: route.polyline.points(), count: route.polyline.pointCount)
            map.addOverlay(casing, level: .aboveRoads)
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

        // Kamera hedefi: sadece merkezi kaydır, zoom/pitch korunur (2D kalır)
        if let target = cameraTarget {
            var cam = map.camera
            cam.centerCoordinate = target
            map.setCamera(cam, animated: true)
            DispatchQueue.main.async {
                // Tek seferlik uygula, sürekli zıplamasın
                cameraTarget = nil
            }
        } else if let first = initialCenter {
            // Açılış: 2D tepeden, sokak seviyesi yakınlık
            let camera = MKMapCamera(
                lookingAtCenter: first,
                fromDistance: 1500,
                pitch: 0,
                heading: 0
            )
            map.setCamera(camera, animated: false)
            DispatchQueue.main.async {
                initialCenter = nil
            }
        } else if let start = navStartCenter {
            // Navigasyon Başla: 2D tepeden yakın zoom (pitch hep 0)
            let camera = MKMapCamera(
                lookingAtCenter: start,
                fromDistance: 500,
                pitch: 0,
                heading: 0
            )
            map.setCamera(camera, animated: true)
            DispatchQueue.main.async {
                navStartCenter = nil
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
        let c = Coordinator()
        c.onTap = { self.tapTick += 1 }
        c.onPan = { self.panTick += 1 }
        return c
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var last3D = false
        var onTap: (() -> Void)?
        var onPan: (() -> Void)?

        @objc func handleTap() { onTap?() }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { onPan?() }
        }

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
            if overlay is RouteCasingPolyline, let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .white
                r.lineWidth = 11
                r.lineCap = .round
                r.lineJoin = .round
                r.alpha = 0.9
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

/// Rota beyaz zemini: mavi hattın altında daha kalın beyaz çizgi.
final class RouteCasingPolyline: MKPolyline {}

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
                                .buttonStyle(.plain)
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
