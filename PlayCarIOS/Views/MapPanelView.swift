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
    @State private var cameraTarget: CLLocationCoordinate2D?
    @State private var selectedPlace: MKMapItem?
    @State private var selectedSubtitle = ""
    @State private var is3D = false
    @State private var showTraffic = true
    @State private var followUser = true
    @State private var showFavorites = false

    var body: some View {
        ZStack(alignment: .top) {
            CarMapView(
                userLocation: locationManager.lastLocation?.coordinate,
                selectedPlace: $selectedPlace,
                cameraTarget: $cameraTarget,
                is3D: is3D,
                showTraffic: showTraffic,
                followUser: followUser,
                favorites: favorites.favorites
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                SearchBarView(searchService: searchService) { completion in
                    searchService.resolve(completion) { item in
                        guard let item else { return }
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
                .padding(.horizontal, 12)
                .padding(.top, 10)

                if locationManager.authState != .authorized {
                    LocationPermissionBanner(
                        state: locationManager.authState,
                        onRequest: { locationManager.requestPermission() }
                    )
                    .padding(.horizontal, 12)
                }
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    // Seçili yer kartı: Apple Maps'teki gibi favoriye ekle + kapat
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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: 320)
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                    } else {
                        Spacer(minLength: 0)
                    }
                    Spacer()
                    MapControls(
                        is3D: $is3D,
                        showTraffic: $showTraffic,
                        followUser: $followUser,
                        onRecenter: {
                            followUser = true
                            selectedPlace = nil
                            if let coord = locationManager.lastLocation?.coordinate {
                                cameraTarget = coord
                            }
                        },
                        onFavorites: { showFavorites = true }
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startTracking()
        }
        .onChange(of: locationManager.lastLocation?.coordinate.latitude) { _, _ in
            guard let coord = locationManager.lastLocation?.coordinate else { return }
            searchService.updateRegion(around: coord)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheetView(
                favorites: favorites,
                onGo: { place in
                    selectedPlace = nil
                    followUser = false
                    cameraTarget = place.coordinate
                    showFavorites = false
                }
            )
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

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
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

// MARK: - Kontroller + izin banner

struct MapControls: View {
    @Binding var is3D: Bool
    @Binding var showTraffic: Bool
    @Binding var followUser: Bool
    var onRecenter: () -> Void
    var onFavorites: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            controlButton(icon: "location.fill", active: followUser) { onRecenter() }
            controlButton(icon: is3D ? "view.3d" : "view.2d", active: is3D) { is3D.toggle() }
            controlButton(icon: "car.fill", active: showTraffic) { showTraffic.toggle() }
            controlButton(icon: "star.fill", active: false) { onFavorites() }
        }
    }

    private func controlButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(active ? Color.accentColor : Color(.systemGray5).opacity(0.9))
                .foregroundStyle(active ? .white : .primary)
                .clipShape(Circle())
        }
        .accessibilityLabel(Text(icon))
    }
}

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
