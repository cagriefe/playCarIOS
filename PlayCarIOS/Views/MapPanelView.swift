import SwiftUI
import MapKit


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
    @StateObject private var recents = RecentDestinationsStore()
    @StateObject private var shortcutETA = ShortcutETAService()
    @StateObject private var nav = NavigationStore()
    @State private var cameraTarget: CLLocationCoordinate2D?
    @State private var selectedPlace: MKMapItem?
    @State private var selectedSubtitle = ""
    /// Önizlenen rotanın adresi: navigasyon başlayınca son hedeflere yazılır.
    @State private var previewSubtitle = ""
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

                        if searchFocused {
                            if searchService.query.trimmingCharacters(in: .whitespaces).isEmpty && !recents.items.isEmpty {
                                RecentDestinationsList(recents: recents) { destination in
                                    searchFocused = false
                                    go(to: destination)
                                }
                            }
                        } else if nav.phase == .idle && selectedPlace == nil {
                            QuickChipsRow(
                                favorites: favorites,
                                recents: recents,
                                eta: shortcutETA,
                                onGo: { go(to: $0) },
                                onSetUp: { showFavorites = true }
                            )
                            .onAppear(perform: refreshShortcutETAs)
                            .transition(.opacity)
                        }
                    }

                    if locationManager.authState != .authorized {
                        LocationPermissionBanner(
                            state: locationManager.authState,
                            onRequest: { locationManager.requestPermission() }
                        )
                    }

                    // Turn-by-turn kartı: sol panelin üstünde, arama altında sabit
                    NavBannerView(nav: nav) { overviewRoute = nil }
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
                    go(to: QuickDestination(name: place.name, address: place.address, coordinate: place.coordinate))
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
                if let coordinate = nav.destinationCoordinate {
                    recents.add(name: nav.destinationName, address: previewSubtitle, coordinate: coordinate)
                }
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
        previewSubtitle = selectedPlace === item ? selectedSubtitle : ""
        nav.previewRoute(to: item, from: loc)
    }

    /// Favori / kısayol / son hedef: yeri seç ve rota önizlemesini başlat
    /// (konum yoksa sadece oraya git).
    private func go(to destination: QuickDestination) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        item.name = destination.name
        nav.stop()
        overviewRoute = nil
        selectedPlace = item
        selectedSubtitle = destination.address
        followMode = .none
        if locationManager.lastLocation != nil {
            startPreview(for: item)
        } else {
            cameraTarget = destination.coordinate
        }
    }

    private func refreshShortcutETAs() {
        guard let loc = locationManager.lastLocation else { return }
        shortcutETA.refresh(for: favorites.shortcuts, from: loc)
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
