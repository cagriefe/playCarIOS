import Foundation
import CallKit
import UIKit
import Combine

/// Sistem telefon aramasını izler; medya panelindeki arama kartını besler.
/// iOS SINIRI (dürüst not): üçüncü parti uygulamalar GSM aramasını
/// cevaplayamaz / bitiremez / hoparlöre alamaz / arayanı göremez.
/// Bu store aramanın durumunu ve süresini yönetir; kendi favori
/// kişilerimizden başlattığımız aramada kişiyi eşleştirir.
final class CallStore: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Gelen arama çalıyor.
        case incoming
        /// Giden arama, karşı taraf henüz açmadı.
        case dialing
        case active
        case onHold
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedText = "00:00"
    /// Sadece bizim başlattığımız giden aramada bilinir.
    @Published private(set) var contact: FavoriteContact?
    @Published var dismissed = false

    var inCall: Bool { phase != .idle }

    private let observer = CXCallObserver()
    private var timer: Timer?
    /// Çağrı UUID → bağlandığı an (süre buna göre).
    private var connectedAt: [UUID: Date] = [:]
    private var contactsByCall: [UUID: FavoriteContact] = [:]
    private var primaryCall: UUID?
    private var pendingOutgoing: (contact: FavoriteContact, at: Date)?

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
        evaluate()
    }

    deinit {
        timer?.invalidate()
    }

    func show() { dismissed = false }
    func hide() { dismissed = true }

    /// Favori kişiyi ara: iOS önce kendi onay penceresini gösterir.
    func call(_ contact: FavoriteContact) {
        guard let url = contact.callURL else { return }
        pendingOutgoing = (contact, Date())
        UIApplication.shared.open(url)
    }

    // MARK: - Durum

    /// Öncelik: çalan gelen arama (bekleyen arama dahil) > görüşme > aranıyor > beklemede.
    private func evaluate() {
        let calls = observer.calls.filter { !$0.hasEnded }
        let now = Date()

        for call in calls {
            if call.hasConnected, connectedAt[call.uuid] == nil {
                connectedAt[call.uuid] = now
            }
            if call.isOutgoing, contactsByCall[call.uuid] == nil,
               let pending = pendingOutgoing, now.timeIntervalSince(pending.at) < 20 {
                contactsByCall[call.uuid] = pending.contact
                pendingOutgoing = nil
            }
        }
        let live = Set(calls.map(\.uuid))
        connectedAt = connectedAt.filter { live.contains($0.key) }
        contactsByCall = contactsByCall.filter { live.contains($0.key) }

        let ringing = calls.first { !$0.isOutgoing && !$0.hasConnected }
        let talking = calls.first { $0.hasConnected && !$0.isOnHold }
        let dialing = calls.first { $0.isOutgoing && !$0.hasConnected }
        let held = calls.first { $0.hasConnected && $0.isOnHold }

        let newPhase: Phase
        let primary: CXCall?
        if let ringing { newPhase = .incoming; primary = ringing }
        else if let talking { newPhase = .active; primary = talking }
        else if let dialing { newPhase = .dialing; primary = dialing }
        else if let held { newPhase = .onHold; primary = held }
        else { newPhase = .idle; primary = nil }

        if phase == .idle, newPhase != .idle { dismissed = false }
        // Gelen arama her zaman kartı geri getirir (gizlenmiş olsa bile).
        if newPhase == .incoming, phase != .incoming { dismissed = false }

        primaryCall = primary?.uuid
        contact = primary.flatMap { contactsByCall[$0.uuid] }
        if phase != newPhase { phase = newPhase }

        let needsTimer = newPhase == .active || newPhase == .onHold
        if needsTimer { startTimer() } else { stopTimer() }
        tick()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.3
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let id = primaryCall, let start = connectedAt[id] else {
            elapsedText = "00:00"
            return
        }
        let total = Int(Date().timeIntervalSince(start))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        elapsedText = h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

extension CallStore: CXCallObserverDelegate {
    func callObserver(_ observer: CXCallObserver, callChanged call: CXCall) {
        evaluate()
    }
}
