import Foundation
import MapKit
import Combine

/// Ev / İş kısayolu (birden fazla yer aynı etiketi alabilir: iki ev gibi).
enum PlaceKind: String, Codable {
    case home
    case work
}

/// Favori yer modeli. Cihazda saklanır (UserDefaults + JSON),
/// harita pin'i için koordinat döner.
struct FavoritePlace: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date = Date()
    /// Optional: eski kayıtlarda alan yok, decodeIfPresent ile nil gelir.
    var kind: PlaceKind?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Favori yer deposu: ekle / sil / kalıcılık.
/// Tek sorumluluk: favori listesi durumu.
final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [FavoritePlace] = []

    private let storageKey = "favoritePlaces.v1"

    init() {
        load()
    }

    func add(name: String, address: String, coordinate: CLLocationCoordinate2D) {
        guard !contains(coordinate: coordinate) else { return }
        favorites.append(FavoritePlace(
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
        save()
    }

    func remove(_ place: FavoritePlace) {
        favorites.removeAll { $0.id == place.id }
        save()
    }

    func remove(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save()
    }

    var homes: [FavoritePlace] { favorites.filter { $0.kind == .home } }
    var works: [FavoritePlace] { favorites.filter { $0.kind == .work } }
    var shortcuts: [FavoritePlace] { homes + works }

    /// Yeri Ev/İş yapar; nil etiketi kaldırır. Diğer Ev/İş'lere dokunmaz.
    func setKind(_ kind: PlaceKind?, for place: FavoritePlace) {
        guard let i = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[i].kind = kind
        save()
    }

    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        favorites.contains {
            abs($0.latitude - coordinate.latitude) < 1e-4 &&
            abs($0.longitude - coordinate.longitude) < 1e-4
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FavoritePlace].self, from: data)
        else { return }
        favorites = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
