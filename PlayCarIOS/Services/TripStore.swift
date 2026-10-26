import Foundation
import CoreLocation
import Combine

/// Yolculuk özeti: gidilen mesafe, sürüş süresi, ortalama ve en yüksek hız.
/// Uygulama açılınca başlar, "Sıfırla" ile yeniden başlar.
/// GPS titremesi sayılmaz: sadece hareket halindeyken (≥ 1 m/s) ve makul
/// sıçramalarda toplanır; uzun boşluklar (tünel, arka plan) atlanır.
final class TripStore: ObservableObject {
    @Published private(set) var distance: CLLocationDistance = 0
    /// Hareket halinde geçen süre (trafikte beklemeler hariç).
    @Published private(set) var drivingTime: TimeInterval = 0
    @Published private(set) var maxSpeed: CLLocationSpeed = 0
    @Published private(set) var startDate: Date

    /// ~306 km/h üstü GPS hatası sayılır.
    private static let maxPlausibleSpeed: CLLocationSpeed = 85
    private var last: CLLocation?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        startDate = now()
    }

    /// m/s
    var averageSpeed: CLLocationSpeed {
        drivingTime > 0 ? distance / drivingTime : 0
    }

    func update(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }
        if location.speed >= 0, location.speed < Self.maxPlausibleSpeed,
           location.speedAccuracy < 0 || location.speedAccuracy <= 5,
           location.speed > maxSpeed {
            maxSpeed = location.speed
        }
        defer { last = location }
        guard let previous = last else { return }
        let dt = location.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0, dt <= 10 else { return }
        let d = location.distance(from: previous)
        guard location.speed >= 1, d <= Self.maxPlausibleSpeed * dt else { return }
        distance += d
        drivingTime += dt
    }

    func reset() {
        distance = 0
        drivingTime = 0
        maxSpeed = 0
        startDate = now()
        last = nil
    }
}

/// Yolculuk kartı biçimleri (değer ve birim ayrı).
enum TripFormat {
    /// "12,4" + "km" / "7.7" + "mi"; 100'den büyükse ondalıksız.
    static func distance(_ meters: Double, imperial: Bool = NavFormat.usesImperial,
                         locale: Locale = .current) -> (value: String, unit: String) {
        let amount = imperial ? meters / 1609.344 : meters / 1000
        let digits = amount >= 100 ? 0 : 1
        return (amount.formatted(.number.precision(.fractionLength(digits)).locale(locale)), imperial ? "mi" : "km")
    }

    /// Hız, görüntü biriminde tam sayı.
    static func speed(_ metersPerSecond: Double, imperial: Bool = NavFormat.usesImperial) -> Int {
        Int((metersPerSecond * (imperial ? 2.236936 : 3.6)).rounded())
    }

    /// "0:23", "1:05" (saat:dakika).
    static func drivingTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
