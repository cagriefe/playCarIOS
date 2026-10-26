import Foundation
import CoreLocation
import Combine

/// Konum + hız + pusula için tek sorumluluk sahibi servis.
/// - CLLocation.speed m/s cinsindendir, negatif = geçersiz.
/// - UI km/h ister: kmh = max(0, speed * 3.6)
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    enum AuthState: Equatable {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    @Published var lastLocation: CLLocation?
    @Published var speedKmh: Double = 0
    @Published var headingDegrees: Double = 0
    @Published var authState: AuthState = .notDetermined
    @Published var lastError: String?

    private let manager = CLLocationManager()
    /// Navigasyon aktifken tam güç, değilken tasarruflu profil.
    private var navigationActive = false
    private var lastPublishedSpeedKmh: Double = -1
    private var lastPublishedHeading: Double = -1

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        // Otomatik duraklatma kapalı: iOS kırmızı ışıkta/trafikte GPS'i durdurur
        // ve kendiliğinden geri AÇMAZ — hız ibresi ve navigasyon donar.
        manager.pausesLocationUpdatesAutomatically = false
        // Mesafe filtresi yok: filtre varken araç durduğunda yeni fix gelmez,
        // hız ibresi son değerde (örn. 8 km/h) takılı kalır.
        manager.distanceFilter = kCLDistanceFilterNone
        applyPowerProfile()
        syncAuthState(status: manager.authorizationStatus)
    }

    /// Navigasyon fazına göre güç profili: navigasyonda .bestForNavigation,
    /// diğer zamanlarda .best (hız ibresi için yeterli).
    func setNavigationActive(_ active: Bool) {
        guard navigationActive != active else { return }
        navigationActive = active
        applyPowerProfile()
    }

    private func applyPowerProfile() {
        if navigationActive {
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.headingFilter = 3
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.headingFilter = 5
        }
        // Arka-plan GPS sadece navigasyonda (yoksa pil biter).
        manager.allowsBackgroundLocationUpdates = navigationActive
        manager.showsBackgroundLocationIndicator = navigationActive
    }

    func requestPermission() {
        lastError = nil
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        guard authState == .authorized else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        syncAuthState(status: manager.authorizationStatus)
        if authState == .authorized {
            startTracking()
        } else {
            stopTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Negatif horizontalAccuracy = geçersiz fix, hızı 0 kabul et.
        guard loc.horizontalAccuracy >= 0 else { return }
        lastLocation = loc

        let rawSpeed = loc.speed // m/s, <0 ise geçersiz
        let kmh = rawSpeed >= 0 ? rawSpeed * 3.6 : 0
        // Gereksiz SwiftUI redraw'u engelle: 0.5 km/h altı değişimi yayınlama.
        // Hız ibresi yine akıcı (GPS zaten 1 Hz), sadece titreme gider.
        if lastPublishedSpeedKmh < 0 || abs(kmh - lastPublishedSpeedKmh) >= 0.5 || (kmh < 1) != (lastPublishedSpeedKmh < 1) {
            lastPublishedSpeedKmh = kmh
            speedKmh = kmh
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        // Pusula redraw'unu kıs: 3° altı değişimi yayınlama (sargı farkı dahil).
        if lastPublishedHeading < 0 {
            lastPublishedHeading = h
            headingDegrees = h
            return
        }
        var delta = abs(h - lastPublishedHeading).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta = 360 - delta }
        if delta >= 3 {
            lastPublishedHeading = h
            headingDegrees = h
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }

    // MARK: - Helpers

    /// Kısa kardinal yön (uygulama dilinde): N/NE/E… veya K/KD/D…
    var cardinalDirection: String {
        let dirs = [
            String(localized: "N", comment: "Compass: north"),
            String(localized: "NE", comment: "Compass: northeast"),
            String(localized: "E", comment: "Compass: east"),
            String(localized: "SE", comment: "Compass: southeast"),
            String(localized: "S", comment: "Compass: south"),
            String(localized: "SW", comment: "Compass: southwest"),
            String(localized: "W", comment: "Compass: west"),
            String(localized: "NW", comment: "Compass: northwest"),
        ]
        let idx = Int((headingDegrees + 22.5) / 45.0) % 8
        return dirs[idx]
    }

    private func syncAuthState(status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            authState = .notDetermined
        case .denied:
            authState = .denied
        case .restricted:
            authState = .restricted
        case .authorizedAlways, .authorizedWhenInUse:
            authState = .authorized
        @unknown default:
            authState = .notDetermined
        }
    }
}
