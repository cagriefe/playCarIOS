import Foundation
import MapKit
import Combine

/// Navigasyon başlatılmış son hedefler (en yeni başta).
struct RecentDestination: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var date: Date = Date()

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Son hedefler deposu: en fazla 8 kayıt, aynı yer (~100 m) tekrar
/// eklenince başa taşınır. Cihazda saklanır (UserDefaults + JSON).
final class RecentDestinationsStore: ObservableObject {
    static let limit = 8

    @Published private(set) var items: [RecentDestination] = []

    private let storageKey = "recentDestinations.v1"

    init() {
        load()
    }

    func add(name: String, address: String, coordinate: CLLocationCoordinate2D) {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        items.removeAll {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here) < 100
        }
        items.insert(RecentDestination(
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        save()
    }

    func remove(_ item: RecentDestination) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentDestination].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// Ev/İş kısayolları için trafik bilgili süre (MKDirections.calculateETA).
/// Apple istek kotası için önbellekli: 5 dk veya 500 m'den önce yenilenmez.
final class ShortcutETAService: ObservableObject {
    @Published private(set) var travelTimes: [UUID: TimeInterval] = [:]

    private var cache: [UUID: (at: Date, from: CLLocation, target: CLLocationCoordinate2D)] = [:]
    private var inFlight: Set<UUID> = []

    func refresh(for places: [FavoritePlace], from location: CLLocation) {
        for place in places {
            if let c = cache[place.id],
               Date().timeIntervalSince(c.at) < 300,
               c.from.distance(from: location) < 500,
               c.target.latitude == place.latitude, c.target.longitude == place.longitude {
                continue
            }
            guard !inFlight.contains(place.id) else { continue }
            inFlight.insert(place.id)

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
            request.transportType = .automobile
            let id = place.id
            let target = place.coordinate
            MKDirections(request: request).calculateETA { [weak self] response, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inFlight.remove(id)
                    guard let time = response?.expectedTravelTime else { return }
                    self.cache[id] = (Date(), location, target)
                    self.travelTimes[id] = time
                }
            }
        }
    }

    /// "23 dk" / "23 min", "1 sa 5 dk" / "1 hr, 5 min".
    func text(for place: FavoritePlace) -> String? {
        guard let t = travelTimes[place.id] else { return nil }
        return NavFormat.duration(t)
    }
}
