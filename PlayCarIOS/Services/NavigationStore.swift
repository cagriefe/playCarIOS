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
    @Published private(set) var nextManeuver: Maneuver = .straight
    /// Sıradaki manevradan hemen sonra (< 200 m) gelen manevra: "Ardından …".
    @Published private(set) var thenInstruction: String?
    @Published private(set) var thenManeuver: Maneuver?
    @Published private(set) var nextDistance: Double = 0
    @Published private(set) var distanceRemaining: Double = 0
    @Published private(set) var eta: Date?
    /// Sesli yönlendirme varsayılan kapalı; her yeni rotada kapalı başlar.
    @Published var muted = true {
        didSet { if muted { speaker.stopSpeaking(at: .immediate) } }
    }
    @Published var lastError: String?
    /// Türkçe ses yoksa iOS sessizce varsayılan dile düşer — bunu yakala.
    @Published private(set) var turkishVoiceMissing = false

    private var destination: MKMapItem?
    private var destinationLocation: CLLocation?
    private var activeRequest: MKDirections?
    private var lastRecalc = Date.distantPast
    private var lastKnownLocation: CLLocation?
    private var stepGeometry: [StepGeometry] = []
    private var stepManeuvers: [Maneuver] = []
    private var offRouteStrikes = 0
    private var silentUpdate = false
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
        muted = true
        destination = item
        let c = item.placemark.coordinate
        destinationLocation = CLLocation(latitude: c.latitude, longitude: c.longitude)
        destinationName = item.name ?? "Varış noktası"
        lastKnownLocation = userLocation
        phase = .calculating
        calculate(from: userLocation) { [weak self] route in
            guard let self else { return }
            guard let route else {
                self.phase = .idle
                self.lastError = "Rota hesaplanamadı. İnterneti kontrol edin."
                return
            }
            self.setRoute(route)
            self.phase = .preview
            self.refreshPreviewStats()
            #if DEBUG
            self.debugDump(route)
            #endif
        }
    }

    func start() {
        guard phase == .preview, let route else { return }
        currentStepIndex = Self.firstDrivableStep(in: route)
        offRouteStrikes = 0
        phase = .navigating
        // Başlangıç manevrası ("Cezayir Cd.'ye sağa dönün") hemen okunur,
        // ardından sıradaki manevra mesafesiyle birlikte kuyruğa girer.
        let startText = route.steps[currentStepIndex].instructions
        if !startText.isEmpty { speak(startText) }
        if let loc = lastKnownLocation {
            // Sadece konumu/mesafeyi hesapla; anonsu aşağıda tek sefer yap.
            silentUpdate = true
            updateLocation(loc)
            silentUpdate = false
        }
        enterCurrentStep(distanceToManeuver: nextDistance > 0 ? nextDistance : route.steps[currentStepIndex].distance,
                         queue: !startText.isEmpty)
    }

    func stop(clearDestination: Bool = true) {
        activeRequest?.cancel()
        activeRequest = nil
        speaker.stopSpeaking(at: .immediate)
        releaseAudioSession()
        route = nil
        stepGeometry = []
        stepManeuvers = []
        if clearDestination { destination = nil; destinationLocation = nil; destinationName = "" }
        currentStepIndex = 0
        nextInstruction = ""
        nextManeuver = .straight
        thenInstruction = nil
        thenManeuver = nil
        nextDistance = 0
        distanceRemaining = 0
        eta = nil
        if phase != .idle { phase = .idle }
    }

    // MARK: - Konum takibi (haritadan her konumda çağrılır)

    /// MapKit adımı: `instructions`, adımın BAŞINDAKİ manevradır
    /// (adım 1 başlangıçta "… sağa dönün", son adım 0 m "Varış").
    /// Yani adım i'de sürerken sıradaki manevra adım i+1'in talimatıdır ve
    /// mesafesi adım i'nin yol boyunca kalan uzunluğudur.
    func updateLocation(_ loc: CLLocation) {
        lastKnownLocation = loc
        guard phase == .navigating, let route else { return }
        let steps = route.steps
        guard steps.indices.contains(currentStepIndex), stepGeometry.count == steps.count else { return }
        // Çok kötü fix'lerle (tünel, kapalı otopark) adım/rota oynatma.
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else { return }

        let p = MKMapPoint(loc.coordinate)
        let current = currentStepIndex

        // Konumu rotaya izdüşür: mevcut adım + önündeki birkaç adım.
        var bestIdx = current
        var best = project(p, ontoStep: current) ?? (offset: .greatestFiniteMagnitude, remaining: 0)
        let upper = min(steps.count - 1, current + 4)
        if upper > current {
            for i in (current + 1)...upper {
                guard let r = project(p, ontoStep: i) else { continue }
                // İleri atlamak için belirgin şekilde daha yakın olmalı (kavşakta titremesin).
                if r.offset < best.offset - 3 {
                    best = r
                    bestIdx = i
                }
            }
        }
        // Adımın sonuna geldiysek bir sonrakine geç (0 m'lik nokta adımlarını atla).
        if best.remaining < 12, let next = nextDrivableStep(after: bestIdx, in: steps),
           let r = project(p, ontoStep: next) {
            bestIdx = next
            best = r
        }

        // Rotadan sapma: üst üste 3 fix 50 m dışında → yeniden hesapla (10 sn kilit).
        if best.offset > 50 {
            offRouteStrikes += 1
        } else {
            offRouteStrikes = 0
        }
        if offRouteStrikes >= 3, Date().timeIntervalSince(lastRecalc) > 10 {
            offRouteStrikes = 0
            lastRecalc = Date()
            recalculate(from: loc)
            return
        }
        guard best.offset <= 50 else { return }

        nextDistance = best.remaining
        if bestIdx != currentStepIndex {
            currentStepIndex = bestIdx
            if !silentUpdate { enterCurrentStep(distanceToManeuver: best.remaining) }
        } else if !silentUpdate {
            announceApproachIfNeeded(speed: loc.speed)
        }
        refreshUpcoming()
        #if DEBUG
        print(String(format: "PCDBG NAV step=%d/%d off=%.0fm next=%.0fm instr=%@",
                     currentStepIndex, steps.count, best.offset, nextDistance, nextInstruction))
        #endif

        let rest = steps.dropFirst(currentStepIndex + 1).reduce(0) { $0 + $1.distance }
        distanceRemaining = rest + nextDistance

        // Varış: hedefe 30 m veya son sürülen adımın sonuna 25 m kala.
        let onFinalLeg = nextDrivableStep(after: currentStepIndex, in: steps) == nil
        let nearDestination = destinationLocation.map { loc.distance(from: $0) < 30 } ?? false
        if nearDestination || (onFinalLeg && best.remaining < 25) {
            phase = .arrived
            nextDistance = 0
            distanceRemaining = 0
            speak("Varış noktasına ulaştınız.")
            return
        }

        // Varış saati: Apple'ın trafik bilgili süresi, kalan mesafe oranında.
        if route.distance > 0 {
            let fraction = min(max(distanceRemaining / route.distance, 0), 1)
            eta = Date().addingTimeInterval(route.expectedTravelTime * fraction)
        }
    }

    /// Manevraya göre kamera yüksekliği (Apple Haritalar gibi adaptif zoom):
    /// manevraya yaklaştıkça yakınlaşır, uzun düzlükte uzaklaşır.
    func altitudeForNextManeuver() -> Double {
        switch nextDistance {
        case ..<250: return 450
        case ..<800: return 700
        case ..<2500: return 1100
        default: return 1700
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
            self.setRoute(route)
            self.currentStepIndex = Self.firstDrivableStep(in: route)
            self.speak("Rota yeniden hesaplandı.")
            self.silentUpdate = true
            self.updateLocation(self.lastKnownLocation ?? userLocation)
            self.silentUpdate = false
            self.enterCurrentStep(distanceToManeuver: self.nextDistance, queue: true)
        }
    }

    private func setRoute(_ route: MKRoute) {
        self.route = route
        stepGeometry = route.steps.map { StepGeometry(polyline: $0.polyline) }
        stepManeuvers = route.steps.indices.map { i in
            ManeuverClassifier.classify(
                instruction: route.steps[i].instructions,
                turnAngle: turnAngle(into: i),
                isLast: i == route.steps.count - 1
            )
        }
        #if DEBUG
        print("PCDBG MANEUVERS " + stepManeuvers.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: " "))
        #endif
    }

    private func refreshPreviewStats() {
        guard let route else { return }
        distanceRemaining = route.distance
        eta = Date().addingTimeInterval(route.expectedTravelTime)
        let first = Self.firstDrivableStep(in: route)
        nextInstruction = route.steps.indices.contains(first) ? route.steps[first].instructions : ""
        nextManeuver = stepManeuvers.indices.contains(first) ? stepManeuvers[first] : .depart
        thenInstruction = nil
        thenManeuver = nil
    }

    /// İlk gerçek adım (0 m'lik başlangıç noktası adımını atla).
    private static func firstDrivableStep(in route: MKRoute) -> Int {
        route.steps.firstIndex(where: { $0.distance > 0 && $0.polyline.pointCount > 1 }) ?? 0
    }

    private func nextDrivableStep(after index: Int, in steps: [MKRoute.Step]) -> Int? {
        guard index + 1 < steps.count else { return nil }
        return steps[(index + 1)...].firstIndex(where: { $0.distance > 0 && $0.polyline.pointCount > 1 })
    }

    /// Sıradaki manevra = mevcut adımdan sonraki adımın talimatı.
    private func upcomingInstruction() -> String {
        guard let steps = route?.steps else { return "" }
        let i = currentStepIndex + 1
        guard steps.indices.contains(i) else { return "Varış noktası" }
        let text = steps[i].instructions
        if text.isEmpty { return "Devam edin" }
        return text
    }

    /// Sıradaki manevra (metin + ikon) ve hemen ardından gelen manevra.
    /// Adım i+1'in talimatı sıradaki manevradır; adım i+1'in uzunluğu
    /// sıradaki ile ondan sonraki manevra arasındaki mesafedir.
    private func refreshUpcoming() {
        nextInstruction = upcomingInstruction()
        let i = currentStepIndex + 1
        nextManeuver = stepManeuvers.indices.contains(i) ? stepManeuvers[i] : .arrive
        var thenText: String?
        var thenMan: Maneuver?
        if let steps = route?.steps, steps.indices.contains(i + 1), steps[i].distance < 200 {
            let raw = steps[i + 1].instructions
            let isLast = i + 1 == steps.count - 1
            if !raw.isEmpty || isLast {
                thenText = raw.isEmpty ? "Varış noktası" : raw
                thenMan = stepManeuvers.indices.contains(i + 1) ? stepManeuvers[i + 1] : nil
            }
        }
        if thenInstruction != thenText { thenInstruction = thenText }
        if thenManeuver != thenMan { thenManeuver = thenMan }
    }

    /// Son anonsa yakın manevrayı ekle: "Sağa dönün, ardından sola dönün".
    private func withThen(_ text: String) -> String {
        guard let then = thenInstruction, !text.isEmpty else { return text }
        let tr = Locale(identifier: "tr_TR")
        let lowered = then.prefix(1).lowercased(with: tr) + then.dropFirst()
        return "\(text), ardından \(lowered)"
    }

    /// Adım `index`'in başındaki dönüş açısı: önceki sürülebilir adımın son
    /// ~30 m'lik yönü ile bu adımın ilk ~30 m'lik yönü arasındaki fark.
    private func turnAngle(into index: Int) -> Double? {
        guard index > 0, stepGeometry.indices.contains(index) else { return nil }
        var p = index - 1
        while p >= 0, stepGeometry[p].length < 1 { p -= 1 }
        guard p >= 0 else { return nil }
        let incoming = stepGeometry[p], outgoing = stepGeometry[index]
        guard outgoing.length >= 1,
              let inBearing = ManeuverClassifier.bearing(
                from: incoming.point(at: max(incoming.length - 30, 0)),
                to: incoming.point(at: incoming.length)),
              let outBearing = ManeuverClassifier.bearing(
                from: outgoing.point(at: 0),
                to: outgoing.point(at: min(30, outgoing.length)))
        else { return nil }
        return ManeuverClassifier.turnAngle(inBearing: inBearing, outBearing: outBearing)
    }

    /// Yeni adıma girildi (manevra yapıldı): sıradaki manevrayı oku.
    /// Uzaksa mesafesiyle ("800 metre sonra, sağa dönün"), yakınsa doğrudan.
    private func enterCurrentStep(distanceToManeuver: Double, queue: Bool = false) {
        guard phase == .navigating else { return }
        refreshUpcoming()
        let text = nextInstruction
        announcedApproach = distanceToManeuver < 700
        announcedFinal = distanceToManeuver < 150
        if distanceToManeuver >= 150 {
            speak("\(NavFormat.spokenDistance(distanceToManeuver)) sonra, \(text)", queue: queue)
        } else {
            speak(withThen(text), queue: queue)
        }
    }

    /// Manevra öncesi hatırlatmalar: ~400 m'de bir kez, son ~100 m'de bir kez.
    /// Hızlıyken son anons biraz daha erken (≈7 sn önce) yapılır.
    private func announceApproachIfNeeded(speed: CLLocationSpeed) {
        let text = upcomingInstruction()
        let finalThreshold = max(100, (speed > 0 ? speed : 0) * 7)
        if !announcedFinal, nextDistance <= finalThreshold {
            announcedFinal = true
            announcedApproach = true
            speak(withThen(text))
        } else if !announcedApproach, nextDistance <= 400 {
            announcedApproach = true
            speak("\(NavFormat.spokenDistance(nextDistance)) sonra, \(text)")
        }
    }

    private func speak(_ text: String, queue: Bool = false) {
        guard !muted, !text.isEmpty else { return }
        #if DEBUG
        print("PCDBG SPEAK \(text)")
        #endif
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

    // MARK: - Rota geometrisi

    /// Konumun adım çizgisine dik uzaklığı ve adımın yol boyunca kalan uzunluğu.
    /// Kuş uçuşu değil, çizgi üzerinden ölçülür (virajlı yolda doğru mesafe).
    private func project(_ p: MKMapPoint, ontoStep index: Int) -> (offset: Double, remaining: Double)? {
        guard stepGeometry.indices.contains(index) else { return nil }
        let g = stepGeometry[index]
        let pts = g.points
        guard pts.count > 1 else { return nil }
        var bestOffset = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
            t = min(max(t, 0), 1)
            let proj = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            let d = p.distance(to: proj)
            if d < bestOffset {
                bestOffset = d
                bestAlong = g.cumulative[i] + a.distance(to: proj)
            }
        }
        return (bestOffset, max(g.length - bestAlong, 0))
    }
}

/// Adım çizgisinin noktaları + başlangıçtan itibaren birikimli uzunluk (m).
private struct StepGeometry {
    let points: [MKMapPoint]
    let cumulative: [Double]
    var length: Double { cumulative.last ?? 0 }

    /// Çizgi boyunca `distance` metredeki nokta (doğrusal ara değer).
    func point(at distance: Double) -> MKMapPoint {
        guard let first = points.first else { return MKMapPoint() }
        guard distance > 0 else { return first }
        for i in 1..<points.count where cumulative[i] >= distance {
            let segment = cumulative[i] - cumulative[i - 1]
            let t = segment > 0 ? (distance - cumulative[i - 1]) / segment : 0
            let a = points[i - 1], b = points[i]
            return MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return points[points.count - 1]
    }

    init(polyline: MKPolyline) {
        let n = polyline.pointCount
        let ptr = polyline.points()
        var pts: [MKMapPoint] = []
        var cum: [Double] = []
        pts.reserveCapacity(n)
        cum.reserveCapacity(n)
        var total = 0.0
        for i in 0..<n {
            let pt = ptr[i]
            if let last = pts.last { total += last.distance(to: pt) }
            pts.append(pt)
            cum.append(total)
        }
        points = pts
        cumulative = cum
    }
}

#if DEBUG
extension NavigationStore {
    func debugDump(_ route: MKRoute) {
        print("PCDBG ROUTE dist=\(Int(route.distance)) time=\(Int(route.expectedTravelTime)) steps=\(route.steps.count)")
        for (i, s) in route.steps.enumerated() {
            let n = s.polyline.pointCount
            let a = n > 0 ? s.polyline.points()[0].coordinate : kCLLocationCoordinate2DInvalid
            let b = n > 0 ? s.polyline.points()[n - 1].coordinate : kCLLocationCoordinate2DInvalid
            print(String(format: "PCDBG STEP %d dist=%.0f pts=%d start=%.5f,%.5f end=%.5f,%.5f '%@'",
                         i, s.distance, n, a.latitude, a.longitude, b.latitude, b.longitude, s.instructions))
        }
        let n = route.polyline.pointCount
        let pts = route.polyline.points()
        let coords = (0..<n).map { String(format: "%.6f,%.6f", pts[$0].coordinate.latitude, pts[$0].coordinate.longitude) }
        print("PCDBG ROUTEPTS " + coords.joined(separator: " "))
    }
}
#endif

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
