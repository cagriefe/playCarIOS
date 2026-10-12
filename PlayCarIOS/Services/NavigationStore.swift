import Foundation
import MapKit
import AVFoundation
import Combine

/// Sürüş navigasyonu: rota hesaplama (MKDirections), adım takibi,
/// sapma durumunda yeniden hesaplama, Türkçe sesli yönlendirme.
final class NavigationStore: ObservableObject {

    enum Phase: Equatable {
        case idle
        case calculating
        case preview
        case navigating
        case arrived
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var route: MKRoute?
    @Published private(set) var destinationName = ""
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var nextInstruction = ""
    @Published private(set) var nextDistance: Double = 0
    @Published private(set) var distanceRemaining: Double = 0
    @Published private(set) var eta: Date?
    @Published var muted = false
    @Published var lastError: String?

    private var destination: MKMapItem?
    private var activeRequest: MKDirections?
    private var lastRecalc = Date.distantPast
    private var lastOffRouteCheck = Date.distantPast
    private let speaker = AVSpeechSynthesizer()

    // MARK: - Rota

    /// Önizleme rotası hesaplar (haritada çizilir, Başla beklenir).
    func previewRoute(to item: MKMapItem, from userLocation: CLLocation) {
        stop(clearDestination: true)
        lastError = nil
        destination = item
        destinationName = item.name ?? "Varış noktası"
        phase = .calculating
        calculate(from: userLocation) { [weak self] route in
            guard let self else { return }
            guard let route else {
                self.phase = .idle
                self.lastError = "Rota hesaplanamadı. İnterneti kontrol edin."
                return
            }
            self.route = route
            self.phase = .preview
            self.refreshPreviewStats(from: userLocation)
        }
    }

    func start() {
        guard phase == .preview, let steps = route?.steps else { return }
        currentStepIndex = steps.firstIndex(where: { $0.distance > 0 }) ?? 0
        phase = .navigating
        configureAudioSession()
        announceCurrentStep()
    }

    func stop(clearDestination: Bool = true) {
        activeRequest?.cancel()
        activeRequest = nil
        speaker.stopSpeaking(at: .immediate)
        releaseAudioSession()
        route = nil
        if clearDestination { destination = nil; destinationName = "" }
        currentStepIndex = 0
        nextInstruction = ""
        nextDistance = 0
        distanceRemaining = 0
        eta = nil
        if phase != .idle { phase = .idle }
    }

    // MARK: - Konum takibi (haritadan her konumda çağrılır)

    func updateLocation(_ loc: CLLocation) {
        guard phase == .navigating, let route, let dest = destination else { return }
        let steps = route.steps
        guard steps.indices.contains(currentStepIndex) else { return }

        // Varış: hedefe 60 m'den yakın
        let destCoord = dest.placemark.coordinate
        if loc.distance(from: CLLocation(latitude: destCoord.latitude, longitude: destCoord.longitude)) < 60 {
            phase = .arrived
            speak("Varış noktasına ulaştınız.")
            return
        }

        // Adım ilerlet: mevcut adımın sonuna 40 m'den yakınsa
        var idx = currentStepIndex
        while idx + 1 < steps.count,
              distance(from: loc.coordinate, toEndOf: steps[idx].polyline) < 40 {
            idx += 1
        }
        if idx != currentStepIndex {
            currentStepIndex = idx
            announceCurrentStep()
        }

        let current = steps[currentStepIndex]
        nextDistance = distance(from: loc.coordinate, toEndOf: current.polyline)
        nextInstruction = current.instructions.isEmpty ? "Devam edin" : current.instructions

        let rest = steps.dropFirst(currentStepIndex + 1).reduce(0) { $0 + $1.distance }
        distanceRemaining = rest + nextDistance

        let speed = max(loc.speed >= 0 ? loc.speed : 0, 8) // m/s, min ~29 km/h varsayım
        eta = Date().addingTimeInterval(distanceRemaining / speed)

        // Rotadan sapma: 5 sn'de bir kontrol, 80 m dışındaysa yeniden hesapla (15 sn kilit)
        let now = Date()
        if now.timeIntervalSince(lastOffRouteCheck) > 5 {
            lastOffRouteCheck = now
            if distance(from: loc.coordinate, to: route.polyline) > 80,
               now.timeIntervalSince(lastRecalc) > 15 {
                lastRecalc = now
                recalculate(from: loc)
            }
        }
    }

    // MARK: - Private

    /// Manevraya göre kamera yüksekliği (normal Maps gibi adaptif zoom):
    /// yaklaştıça daralır, uzun düzlükte genişler. 2D her zaman (pitch 0).
    func altitudeForNextManeuver() -> Double {
        switch nextDistance {
        case ..<150: return 300
        case ..<500: return 550
        case ..<1500: return 900
        default: return 1600
        }
    }

    private func calculate(from userLocation: CLLocation, completion: @escaping (MKRoute?) -> Void) {
        guard let destination else { completion(nil); return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        activeRequest = directions
        directions.calculate { [weak self] response, error in
            guard let self, self.activeRequest === directions else { return }
            if error != nil { completion(nil); return }
            completion(response?.routes.first)
        }
    }

    private func recalculate(from userLocation: CLLocation) {
        calculate(from: userLocation) { [weak self] route in
            guard let self, self.phase == .navigating, let route else { return }
            self.route = route
            self.currentStepIndex = route.steps.firstIndex(where: { $0.distance > 0 }) ?? 0
            self.updateLocation(userLocation)
        }
    }

    private func refreshPreviewStats(from userLocation: CLLocation) {
        guard let route else { return }
        distanceRemaining = route.distance
        eta = Date().addingTimeInterval(route.expectedTravelTime)
        nextInstruction = route.steps.first(where: { $0.distance > 0 })?.instructions ?? ""
    }

    private func announceCurrentStep() {
        guard phase == .navigating, let steps = route?.steps,
              steps.indices.contains(currentStepIndex) else { return }
        let text = steps[currentStepIndex].instructions
        nextInstruction = text.isEmpty ? "Devam edin" : text
        speak(nextInstruction)
    }

    private func speak(_ text: String) {
        guard !muted, !text.isEmpty else { return }
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.52
        speaker.speak(utterance)
    }

    /// Sesli yönlendirme müziği DURDURMASIN diye: konuşma sırasında
    /// diğer sesi kısmaya (duck) izin veren oturum. Ayarlanmazsa
    /// varsayılan soloAmbient müziği keser.
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            lastError = "Ses çıkışı ayarlanamadı."
        }
    }

    private func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Mesafe yardımcıları

    /// Kullanıcı -> polyline son noktası (adım bitimi).
    private func distance(from coord: CLLocationCoordinate2D, toEndOf polyline: MKPolyline) -> CLLocationDistance {
        guard polyline.pointCount > 0 else { return .greatestFiniteMagnitude }
        let end = polyline.points()[polyline.pointCount - 1].coordinate
        return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    /// Kullanıcı -> polyline üzerindeki en yakın nokta (sapma kontrolü).
    private func distance(from coord: CLLocationCoordinate2D, to polyline: MKPolyline) -> CLLocationDistance {
        guard polyline.pointCount > 0 else { return .greatestFiniteMagnitude }
        let user = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var best = Double.greatestFiniteMagnitude
        let ptr = polyline.points()
        // Uzun rotalarda her noktaya bakmak pahalı; örnekleme ile yaklaş.
        let stride = max(1, polyline.pointCount / 400)
        var i = 0
        while i < polyline.pointCount {
            let p = ptr[i].coordinate
            let d = user.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            if d < best { best = d }
            i += stride
        }
        return best
    }
}

// MARK: - Format

enum NavFormat {
    /// 350 m / 2,3 km (Türkçe ondalık)
    static func distance(_ meters: Double) -> String {
        if meters < 950 {
            return "\(Int(meters.rounded())) m"
        }
        let km = meters / 1000
        return "\(String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")) km"
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
