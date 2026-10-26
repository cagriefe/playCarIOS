import SwiftUI
import MapKit

/// Harita takip modu (Apple Haritalar konum butonu döngüsü):
/// none → follow (kuzey sabit) → heading (yöne dönen) → follow …
enum MapFollowMode: Equatable {
    case none
    case follow
    case heading
}

/// Harita paneli: sol %65.
/// DÜZELTME NOTU: SwiftUI `Map` (iOS 17) trafik katmanı sunmaz.
/// Bu yüzden trafik + 2D/3D + takip için MKMapView UIViewRepresentable kullanıldı.
struct MapPanelView: View {
    @ObservedObject var locationManager: LocationManager
    /// Çentik haritanın solundaysa payı; ray/kartlar çentikten kaçar,
    /// harita ise ekran kenarına kadar uzanır.
    var leadingInset: CGFloat = 0
    @StateObject private var searchService = SearchService()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var nav = NavigationStore()
    @State private var cameraTarget: CLLocationCoordinate2D?
    @State private var selectedPlace: MKMapItem?
    @State private var selectedSubtitle = ""
    @AppStorage("showTraffic") private var showTraffic = true
    @State private var followMode: MapFollowMode = .follow
    @State private var showFavorites = false
    @State private var overviewRoute: MKRoute?
    @State private var initialCenter: CLLocationCoordinate2D?
    @State private var didInitialZoom = false
    @AppStorage("mapStyleLight") private var mapStyleLight = false
    /// Sürüş modu: 4 sn işlemsizlikte ray + arama gizlenir (temiz harita).
    /// Navigasyon kartı ve seçili yer kartı her zaman görünür (güvenlik).
    @State private var controlsVisible = true
    @State private var hideTimer: Timer?
    @State private var mapTapTick = 0
    @State private var mapPanTick = 0
    /// Haritanın kuzeye göre dönüklüğü (pusula butonu için).
    @State private var mapHeading: Double = 0
    @State private var resetNorthTick = 0
    @FocusState private var searchFocused: Bool
    private let geocoder = CLGeocoder()

    var body: some View {
        ZStack(alignment: .top) {
            CarMapView(
                userLocation: locationManager.lastLocation?.coordinate,
                selectedPlace: $selectedPlace,
                cameraTarget: $cameraTarget,
                showTraffic: showTraffic,
                followMode: $followMode,
                favorites: favorites.favorites,
                route: nav.route,
                overviewRoute: $overviewRoute,
                initialCenter: $initialCenter,
                mapStyleLight: mapStyleLight,
                tapTick: $mapTapTick,
                panTick: $mapPanTick,
                mapHeading: $mapHeading,
                resetNorthTick: resetNorthTick,
                isNavigating: nav.phase == .navigating,
                navAltitude: nav.phase == .navigating ? nav.altitudeForNextManeuver() : 0,
                overviewLeftPadding: contentLeading + 10,
                onPickPlace: { item, subtitle in pickPlace(item, subtitle: subtitle) },
                onDropPin: { coord in dropPin(at: coord) }
            )
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 8) {
                // Ray soldadır; sütun onun sağında ortalanır (çakışma yok).
                // Kontroller gizliyken ray da gizli: kartlar haritanın üstüne
                // yapışır ve yatayda tüm genişliğe yayılır.
                Spacer(minLength: controlsVisible ? contentLeading - 12 : max(railLeading - 12, 0))
                VStack(spacing: 8) {
                    // Sadece arama çubuğu otomatik gizlenir; izin ve navigasyon
                    // kartları sürüş güvenliği için her zaman görünür kalır.
                    if controlsVisible {
                        SearchBarView(searchService: searchService, focused: $searchFocused) { completion in
                            searchService.resolve(completion) { item in
                                guard let item else { return }
                                nav.stop()
                                overviewRoute = nil
                                selectedPlace = item
                                selectedSubtitle = completion.subtitle
                                followMode = .none
                                cameraTarget = item.placemark.coordinate
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
                        .transition(.move(edge: .top).combined(with: .opacity))
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
                .frame(maxWidth: controlsVisible ? 360 : .infinity)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .animation(.easeInOut(duration: 0.25), value: controlsVisible)

            // Sol ikon rayı (CarPlay sidebar): dikey ortalı yüzen hap
            HStack {
                VStack {
                    Spacer(minLength: 76)
                    VStack(spacing: 5) {
                        railButton(icon: locationIcon, active: followMode != .none, action: recenter)
                        railButton(icon: "car.fill", active: showTraffic) { showTraffic.toggle() }
                        railButton(icon: mapStyleLight ? "sun.max.fill" : "moon.fill", active: false) { mapStyleLight.toggle() }
                        railButton(icon: "star.fill", active: false) { showFavorites = true }
                    }
                    .padding(5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))

                    // Pusula: harita döndürülmüşse görünür, dokununca kuzeye döner
                    // (Apple Haritalar'daki pusula davranışı).
                    if showCompass {
                        Button {
                            pokeControls()
                            resetNorthTick += 1
                        } label: {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.red)
                                .rotationEffect(.degrees(-mapHeading))
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(.top, 6)
                        .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, railLeading)
            .frame(maxHeight: .infinity)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)

            // Seçili yer kartı (sol altta; navigasyon sırasında banner var diye gizlenir)
            HStack(alignment: .bottom) {
                if let item = selectedPlace, nav.phase == .idle {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name ?? String(localized: "Selected Location"))
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
                                name: item.name ?? String(localized: "Selected Location"),
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
                } else if nav.phase == .navigating && followMode == .none {
                    // Navigasyonda harita elle kaydırıldı: Apple Haritalar'daki
                    // "Yeniden Ortala" — her zaman görünür.
                    Button {
                        followMode = .heading
                        pokeControls()
                    } label: {
                        Label("Re-center", systemImage: "location.north.line.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, contentLeading)
            .padding(.trailing, 12)
            .padding(.bottom, 16)
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
        .onChange(of: locationManager.lastLocation) { _, loc in
            // Her fix'te (sadece enlem değişince değil) çalışır: doğu-batı
            // yönlü sürüşte de navigasyon ilerler.
            guard let loc else { return }
            searchService.updateRegion(around: loc.coordinate)
            if !didInitialZoom {
                // Açılışta bir kez: 2D tepeden kamera
                didInitialZoom = true
                initialCenter = loc.coordinate
            }
            nav.updateLocation(loc)
            #if DEBUG
            if let target = DebugNav.target, !DebugNav.started {
                DebugNav.started = true
                let item = MKMapItem(placemark: MKPlacemark(coordinate: target))
                item.name = "Test Destination"
                startPreview(for: item)
            }
            #endif
        }
        .onChange(of: mapTapTick) {
            // Klavye açıkken haritaya dokunmak klavyeyi kapatır (Apple Haritalar gibi).
            if searchFocused {
                searchFocused = false
            } else {
                toggleControls()
            }
        }
        .onChange(of: mapPanTick) {
            // Kullanıcı haritayı elle kaydırdı: kontrolleri göster
            // (takip modu CarMapView tarafından zaten bırakıldı).
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
        .onChange(of: searchFocused) { _, focused in
            // Yazarken arama çubuğu gizlenmesin.
            if focused {
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
                    followMode = .none
                    if locationManager.lastLocation != nil {
                        startPreview(for: item)
                    } else {
                        cameraTarget = place.coordinate
                    }
                }
            )
        }
        .onChange(of: nav.phase) { _, phase in
            switch phase {
            case .preview:
                // Önizleme: tüm rota kadraja alınır, takip bırakılır.
                followMode = .none
                overviewRoute = nav.route
                #if DEBUG
                if DebugNav.target != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { nav.start() }
                }
                #endif
            case .navigating:
                selectedPlace = nil
                followMode = .heading
            case .idle:
                // Navigasyon bitti: takibe dön, haritayı kuzeye çevir.
                followMode = .follow
                resetNorthTick += 1
            case .calculating, .arrived:
                break
            }
            // Pil: tam güç GPS yalnızca navigasyonda, diğer fazlarda tasarruflu.
            locationManager.setNavigationActive(phase == .navigating)
            pokeControls()
        }
    }

    /// Kontrolleri göster + 4 sn sonra otomatik gizle (temiz sürüş görünümü).
    /// @State atamaları non-mutating setter kullanır, escaping closure'dan çağrılabilir.
    private func pokeControls() {
        controlsVisible = true
        hideTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
        }
        t.tolerance = 0.5
        hideTimer = t
    }

    private func toggleControls() {
        hideTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.25)) { controlsVisible.toggle() }
        if controlsVisible { pokeControls() }
    }

    private func startPreview(for item: MKMapItem) {
        guard let loc = locationManager.lastLocation else {
            nav.lastError = String(localized: "Waiting for your location…")
            return
        }
        nav.previewRoute(to: item, from: loc)
    }

    /// Apple Haritalar konum butonu: takip yok → takip et → yöne göre döndür → takip et…
    /// Navigasyonda doğrudan sürüş kamerasına döner.
    private func recenter() {
        if nav.phase == .navigating {
            followMode = .heading
            return
        }
        switch followMode {
        case .none: followMode = .follow
        case .follow: followMode = .heading
        case .heading: followMode = .follow
        }
    }

    /// Ray: çentik varsa hemen yanında, yoksa kenardan 10 pt içeride.
    private var railLeading: CGFloat {
        leadingInset > 0 ? leadingInset + 4 : 10
    }

    /// Arama sütunu ve alt kartlar rayın sağından başlar (ray 44 + 2×5 pt).
    private var contentLeading: CGFloat {
        railLeading + 54 + 10
    }

    private var locationIcon: String {
        switch followMode {
        case .none: return "location"
        case .follow: return "location.fill"
        case .heading: return "location.north.line.fill"
        }
    }

    /// Pusula: harita kuzeyden sapmışsa ve harita kendisi yöne göre dönmüyorsa.
    private var showCompass: Bool {
        let rotated = abs(mapHeading) > 2 && abs(mapHeading - 360) > 2
        let autoRotating = followMode == .heading
        return rotated && !autoRotating
    }

    /// Haritada dokunulan mekan (POI) seçildi.
    private func pickPlace(_ item: MKMapItem, subtitle: String) {
        guard nav.phase == .idle else { return }
        selectedPlace = item
        selectedSubtitle = subtitle
    }

    /// Uzun basma: işaretli konum bırak + adresi ters coğrafi kodla.
    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        guard nav.phase == .idle else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = String(localized: "Dropped Pin")
        selectedPlace = item
        selectedSubtitle = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            preferredLocale: .current
        ) { placemarks, _ in
            guard let pm = placemarks?.first, selectedPlace === item else { return }
            let address = MapPlaceFormat.address(of: pm)
            if !address.isEmpty { selectedSubtitle = address }
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
                Text("Calculating route…").font(.caption).foregroundStyle(.primary)
                Spacer()
                Button("Cancel") { nav.stop() }.font(.caption.bold())
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .preview:
            HStack(spacing: 8) {
                Image(systemName: "car.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 0) {
                    Text(nav.destinationName).font(.subheadline.bold()).lineLimit(1)
                    Text("\(NavFormat.distance(nav.distanceRemaining)) • Arrive \(nav.eta.map(NavFormat.time) ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Go") {
                    nav.start()
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                Button("Close") { nav.stop(); overviewRoute = nil }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .navigating:
            VStack(alignment: .leading, spacing: 6) {
                // Apple Haritalar düzeni: solda büyük ok + mesafe, sağda talimat.
                HStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 2) {
                        ManeuverIcon(maneuver: nav.nextManeuver, size: 30)
                        Text(NavFormat.distance(nav.nextDistance))
                            .font(.headline.bold())
                            .foregroundStyle(.green)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 76)
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nav.nextInstruction.isEmpty ? String(localized: "Continue") : nav.nextInstruction)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(NavFormat.distance(nav.distanceRemaining)) left • Arrive \(nav.eta.map(NavFormat.time) ?? "—")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        Button {
                            nav.muted.toggle()
                        } label: {
                            Image(systemName: nav.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.subheadline)
                                .frame(width: 44, height: 30)
                        }
                        .accessibilityLabel(nav.muted ? String(localized: "Unmute voice guidance") : String(localized: "Mute voice guidance"))
                        Button("End") { nav.stop(); overviewRoute = nil }
                            .font(.caption.bold())
                            .frame(width: 52, height: 30)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                if let then = nav.thenInstruction {
                    HStack(spacing: 6) {
                        Text("Then")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if let thenManeuver = nav.thenManeuver {
                            ManeuverIcon(maneuver: thenManeuver, size: 14)
                        }
                        Text(then)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity)
                }

                // Uygulama dilinde ses yüklü değilse konuşma yabancı aksanla olur.
                if nav.voiceMissing {
                    Button { nav.dismissVoiceWarning() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("No \(nav.voiceLanguageName) voice installed. Settings › Accessibility › Spoken Content › Voices")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .arrived:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Arrived: \(nav.destinationName)")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Button("Close") { nav.stop(); overviewRoute = nil }
                    .font(.caption.bold())
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
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
            var rect = overview.polyline.boundingMapRect
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
        let favKey = favorites.map(\.id.uuidString).joined(separator: "|")
        guard selectedKey != c.lastSelectedKey || favKey != c.lastFavKey else { return }
        c.lastSelectedKey = selectedKey
        c.lastFavKey = favKey
        map.removeAnnotations(map.annotations.filter {
            $0 is MKPointAnnotation
        })
        for fav in favorites {
            let ann = FavoriteAnnotation()
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
        guard routeID != c.lastRouteID || showTraffic != c.lastRouteTraffic else { return }
        c.lastRouteID = routeID
        c.lastRouteTraffic = showTraffic
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { $0 is DestinationAnnotation })
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
            parent.tapTick += 1
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
            if annotation is FavoriteAnnotation {
                let id = "favPin"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.glyphImage = UIImage(systemName: "star.fill")
                v.markerTintColor = .systemYellow
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

#if DEBUG
/// Test kancası (sadece DEBUG): `-PCDebugNavTo "lat,lon"` başlatma argümanı
/// ile açılışta o noktaya rota hesaplanır ve navigasyon kendiliğinden başlar.
enum DebugNav {
    static var started = false
    static let target: CLLocationCoordinate2D? = {
        guard let raw = UserDefaults.standard.string(forKey: "PCDebugNavTo") else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }()
}
#endif

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

// MARK: - Arama çubuğu

/// Rota varış noktası (seçili yer / favori pin'lerinden bağımsız).
final class DestinationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// Favori pin'lerini varsayılan pinden ayırmak için alt sınıf.
final class FavoriteAnnotation: MKPointAnnotation {}

struct SearchBarView: View {
    @ObservedObject var searchService: SearchService
    var focused: FocusState<Bool>.Binding
    var onSelect: (MKLocalSearchCompletion) -> Void
    var onSave: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search for a place or address", text: $searchService.query)
                        .focused(focused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit { focused.wrappedValue = false }
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
                if focused.wrappedValue {
                    Button("Cancel") {
                        searchService.query = ""
                        focused.wrappedValue = false
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if focused.wrappedValue && !searchService.completions.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.completions, id: \.self) { c in
                            HStack(spacing: 0) {
                                Button {
                                    focused.wrappedValue = false
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
                        Text("No Favorites Yet")
                            .font(.headline)
                        Text("Add places with ★ in search results or on the selected place card.")
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
                            .buttonStyle(.plain)
                        }
                        .onDelete { favorites.remove(at: $0) }
                    }
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
            Button("Allow", action: onRequest)
                .font(.caption.bold())
            Button("Settings") {
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
        case .denied: return String(localized: "Location is off. Speed and map won't work.")
        case .restricted: return String(localized: "Location is restricted.")
        case .notDetermined: return String(localized: "Location access is needed for the map.")
        case .authorized: return ""
        }
    }
}
