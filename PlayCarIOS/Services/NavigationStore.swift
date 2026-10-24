import Foundation
import MapKit
import AVFoundation
import Combine

/// Sürüş navigasyonu: rota hesaplama (MKDirections), adım takibi,
/// sapma durumunda yeniden hesaplama, Türkçe sesli yönlendirme.
final class NavigationStore: NSObject, ObservableObject {

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
    @Published var muted = false {
        didSet { if muted { speaker.stopSpeaking(at: .immediate) } }
    }
    @Published var lastError: String?
    /// Türkçe ses yoksa iOS sessizce varsayılan dile düşer — bunu yakala.
    @Published private(set) var turkishVoiceMissing = false

    private var destination: MKMapItem?
    private var destinationLocation: CLLocation?
    private var activeRequest: MKDirections?
    private var lastRecalc = Date.distantPast
    private var lastOffRouteCheck = Date.distantPast
    private let speaker = AVSpeechSynthesizer()
    private var voiceWarningSnoozed = false
    private var cachedTurkishVoice: AVSpeechSynthesisVoice?

    /// Adım içi anons durumu: aynı hatırlatma iki kez okunmasın.
    private var announcedApproach = false
    private var announcedFinal = false

    override init() {
        super.init()
        speaker.delegate = self
    }

    /// "Türkçe ses yok" uyarısını kapat (oturumluk).
    func dismissTurkishVoiceWarning() {
        turkishVoiceMissing = false
        voiceWarningSnoozed = true
    }

    // MARK: - Rota

    /// Önizleme rotası hesaplar (haritada çizilir, Başla beklenir).
    func previewRoute(to item: MKMapItem, from userLocation: CLLocation) {
        stop(clearDestination: true)
        lastError = nil
        destination = item
        let c = item.placemark.coordinate
        destinationLocation = CLLocation(latitude: c.latitude, longitude: c.longitude)
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
            self.refreshPreviewStats()
        }
    }

    func start() {
        guard phase == .preview, let steps = route?.steps else { return }
        currentStepIndex = steps.firstIndex(where: { $0.distance > 0 }) ?? 0
        phase = .navigating
        enterCurrentStep(distanceToManeuver: steps[currentStepIndex].distance)
    }

    func stop(clearDestination: Bool = true) {
        activeRequest?.cancel()
        activeRequest = nil
        speaker.stopSpeaking(at: .immediate)
        releaseAudioSession()
        route = nil
        if clearDestination { destination = nil; destinationLocation = nil; destinationName = "" }
        currentStepIndex = 0
        nextInstruction = ""
        nextDistance = 0
        distanceRemaining = 0
        eta = nil
        if phase != .idle { phase = .idle }
    }

    // MARK: - Konum takibi (haritadan her konumda çağrılır)

    func updateLocation(_ loc: CLLocation) {
        guard phase == .navigating, let route, let dest = destinationLocation else { return }
        let steps = route.steps
        guard steps.indices.contains(currentStepIndex) else { return }

        // Varış: hedefe 40 m'den yakın
        if loc.distance(from: dest) < 40 {
            phase = .arrived
            nextDistance = 0
            distanceRemaining = 0
            speak("Varış noktasına ulaştınız.")
            return
        }

        // Adım ilerlet: mevcut adımın sonuna 35 m'den yakınsa
        var idx = currentStepIndex
        while idx + 1 < steps.count,
              distance(from: loc.coordinate, toEndOf: steps[idx].polyline) < 35 {
            idx += 1
        }
        let current = steps[idx]
        nextDistance = distance(from: loc.coordinate, toEndOf: current.polyline)
        if idx != currentStepIndex {
            currentStepIndex = idx
            enterCurrentStep(distanceToManeuver: nextDistance)
        } else {
            announceApproachIfNeeded(stepLength: current.distance, speed: loc.speed)
        }
        nextInstruction = instruction(of: current)

        let rest = steps.dropFirst(currentStepIndex + 1).reduce(0) { $0 + $1.distance }
        distanceRemaining = rest + nextDistance

        // Varış saati: Apple'ın trafik bilgili süresi, kalan mesafe oranında.
        // Anlık hıza bölmek kırmızı ışıkta/otoyolda ETA'yı zıplatıyordu.
        if route.distance > 0 {
            let fraction = min(max(distanceRemaining / route.distance, 0), 1)
            eta = Date().addingTimeInterval(route.expectedTravelTime * fraction)
        }

        // Rotadan sapma: 4 sn'de bir kontrol, 60 m dışındaysa yeniden hesapla (12 sn kilit).
        // Doğruluğu kötü fix'lerle (tünel vb.) yanlış alarm verme.
        let now = Date()
        if now.timeIntervalSince(lastOffRouteCheck) > 4, loc.horizontalAccuracy < 50 {
            lastOffRouteCheck = now
            if distance(from: loc.coordinate, to: route.polyline) > 60,
               now.timeIntervalSince(lastRecalc) > 12 {
                lastRecalc = now
                recalculate(from: loc)
            }
        }
    }

    /// Manevraya göre kamera yüksekliği (Apple Haritalar gibi adaptif zoom):
    /// manevraya yaklaştıkça yakınlaşır, uzun düzlükte uzaklaşır.
    func altitudeForNextManeuver() -> Double {
        switch nextDistance {
        case ..<200: return 350
        case ..<600: return 600
        case ..<2000: return 1000
        default: return 1600
        }
    }

    // MARK: - Private

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
            self.speak("Rota yeniden hesaplandı.")
            self.enterCurrentStep(
                distanceToManeuver: self.distance(
                    from: userLocation.coordinate,
                    toEndOf: route.steps[self.currentStepIndex].polyline
                ),
                queue: true
            )
            self.updateLocation(userLocation)
        }
    }

    private func refreshPreviewStats() {
        guard let route else { return }
        distanceRemaining = route.distance
        eta = Date().addingTimeInterval(route.expectedTravelTime)
        nextInstruction = route.steps.first(where: { $0.distance > 0 })?.instructions ?? ""
    }

    private func instruction(of step: MKRoute.Step) -> String {
        step.instructions.isEmpty ? "Devam edin" : step.instructions
    }

    /// Yeni adıma girildi: manevra uzaksa mesafesiyle birlikte oku
    /// ("800 metre sonra, sağa dönün"), yakınsa doğrudan talimatı oku.
    private func enterCurrentStep(distanceToManeuver: Double, queue: Bool = false) {
        guard phase == .navigating, let steps = route?.steps,
              steps.indices.contains(currentStepIndex) else { return }
        let text = instruction(of: steps[currentStepIndex])
        nextInstruction = text
        announcedApproach = distanceToManeuver < 700
        announcedFinal = distanceToManeuver < 150
        if distanceToManeuver >= 150 {
            speak("\(NavFormat.spokenDistance(distanceToManeuver)) sonra, \(text)", queue: queue)
        } else {
            speak(text, queue: queue)
        }
    }

    /// Manevra öncesi hatırlatmalar: ~400 m'de bir kez, son ~100 m'de bir kez.
    /// Hızlıyken son anons biraz daha erken (≈7 sn önce) yapılır.
    private func announceApproachIfNeeded(stepLength: Double, speed: CLLocationSpeed) {
        guard steps.indices.contains(currentStepIndex) else { return }
        let text = instruction(of: steps[currentStepIndex])
        let finalThreshold = max(100, (speed > 0 ? speed : 0) * 7)
        if !announcedFinal, nextDistance <= finalThreshold {
            announcedFinal = true
            announcedApproach = true
            speak(text)
        } else if !announcedApproach, nextDistance <= 400 {
            announcedApproach = true
            speak("\(NavFormat.spokenDistance(nextDistance)) sonra, \(text)")
        }
    }

    private var steps: [MKRoute.Step] { route?.steps ?? [] }

    private func speak(_ text: String, queue: Bool = false) {
        guard !muted, !text.isEmpty else { return }
        if !queue { speaker.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        let voice = bestTurkishVoice()
        utterance.voice = voice
        if voice == nil && !voiceWarningSnoozed {
            turkishVoiceMissing = true
        }
        utterance.rate = 0.52
        activateAudioSession()
        speaker.speak(utterance)
    }

    /// Yüklü Türkçe sesler arasından en kalitelisi: premium > enhanced > default.
    /// Bulunamazsa her seferinde yeniden bakılır (kullanıcı Ayarlar'dan indirmiş olabilir).
    private func bestTurkishVoice() -> AVSpeechSynthesisVoice? {
        if let cachedTurkishVoice { return cachedTurkishVoice }
        let tr = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("tr")
        }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            let langScore = (v.language == "tr-TR") ? 0 : 1
            let qualityScore: Int
            switch v.quality {
            case .premium: qualityScore = 0
            case .enhanced: qualityScore = 1
            default: qualityScore = 2
            }
            return langScore * 10 + qualityScore
        }
        let best = tr.min { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: "tr-TR")
        cachedTurkishVoice = best
        if best != nil { turkishVoiceMissing = false }
        return best
    }

    /// Müziği DURDURMADAN sadece konuşma süresince kıs (duck).
    /// Oturum her anonsta açılır, anons bitince kapatılır — böylece
    /// müzik navigasyonun geri kalanında normal seviyede çalar.
    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
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
        let end = polyline.points()[polyline.pointCount - 1]
        return MKMapPoint(coord).distance(to: end)
    }

    /// Kullanıcı -> polyline'a en kısa mesafe (nokta değil, SEGMENT bazlı).
    /// Otoyolda rota noktaları yüzlerce metre aralıklı olabilir; sadece
    /// noktalara bakmak yolun üstündeyken bile "sapma" sanıp rota yeniliyordu.
    private func distance(from coord: CLLocationCoordinate2D, to polyline: MKPolyline) -> CLLocationDistance {
        let count = polyline.pointCount
        guard count > 0 else { return .greatestFiniteMagnitude }
        let p = MKMapPoint(coord)
        let pts = polyline.points()
        if count == 1 { return p.distance(to: pts[0]) }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(count - 1) {
            let a = pts[i], b = pts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
            t = min(max(t, 0), 1)
            let proj = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            let d = p.distance(to: proj)
            if d < best { best = d }
        }
        return best
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension NavigationStore: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.speaker.isSpeaking else { return }
            self.releaseAudioSession()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.speaker.isSpeaking else { return }
            self.releaseAudioSession()
        }
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

    /// Sesli okunuş: "300 metre", "1,5 kilometre" (50 m'ye yuvarlanır).
    static func spokenDistance(_ meters: Double) -> String {
        if meters < 950 {
            let rounded = max(50, Int((meters / 50).rounded()) * 50)
            return "\(rounded) metre"
        }
        let km = (meters / 100).rounded() / 10
        if km == km.rounded() {
            return "\(Int(km)) kilometre"
        }
        return "\(String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")) kilometre"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
