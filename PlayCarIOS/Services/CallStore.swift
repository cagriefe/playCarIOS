import Foundation
import CallKit
import Combine

/// Sistem telefon aramasını izler ve süre kartı sunar.
/// iOS SINIRI (dürüst not): üçüncü parti uygulamalar aramayı
/// bitiremez / cevaplayamaz / arayanı göremez. Bu store sadece
/// "arama sürüyor + kaç dk oldu" bilgisini ve gizlenebilir
/// bir kartı yönetir; arama iPhone'un kendi ekranından yönetilir.
final class CallStore: NSObject, ObservableObject {
    @Published private(set) var inCall = false
    @Published private(set) var elapsedText = "00:00"
    @Published var dismissed = false

    private let observer = CXCallObserver()
    private var timer: Timer?
    private var startDate: Date?

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    deinit {
        timer?.invalidate()
    }

    func show() { dismissed = false }
    func hide() { dismissed = true }

    private func startTimer() {
        timer?.invalidate()
        startDate = Date()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startDate = nil
    }

    private func tick() {
        guard let start = startDate else { return }
        let total = Int(Date().timeIntervalSince(start))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            elapsedText = String(format: "%d:%02d:%02d", h, m, s)
        } else {
            elapsedText = String(format: "%02d:%02d", m, s)
        }
    }
}

extension CallStore: CXCallObserverDelegate {
    func callObserver(_ observer: CXCallObserver, callChanged call: CXCall) {
        let active = observer.calls.contains { !$0.hasEnded && $0.hasConnected }
        if active, !inCall {
            inCall = true
            dismissed = false
            startTimer()
        } else if !active, inCall {
            inCall = false
            stopTimer()
        }
    }
}
