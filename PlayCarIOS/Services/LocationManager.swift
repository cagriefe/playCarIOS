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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // Hız ibresi için heading gerekli (pusula widget'ı).
        manager.headingFilter = 1
        syncAuthState(status: manager.authorizationStatus)
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
        if rawSpeed >= 0 {
            speedKmh = rawSpeed * 3.6
        } else {
            speedKmh = 0
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }

    // MARK: - Helpers

    /// Türkçe kardinal yön: K, KD, D, GD, G, GB, B, KB
    var cardinalDirectionTR: String {
        let dirs = ["K", "KD", "D", "GD", "G", "GB", "B", "KB"]
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
