import Foundation
import UIKit
import Combine

/// Saat / tarih / pil için hafif store.
/// UIDevice.isBatteryMonitoringEnabled = true gerekir (init'te açılır).
final class TelemetryStore: ObservableObject {
    @Published var now = Date()
    @Published var batteryLevel: Float = -1

    private var timer: Timer?

    // DateFormatter pahalı: her saniye yaratma, statik önbellekle.
    // Bölgeye göre: 24 saat / 12 saat (AM/PM), "26 Eki Pzt" / "Mon, Oct 26".
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        // İzleme açıldıktan sonra gerçek değeri oku (öncesinde -1 döner).
        self.batteryLevel = UIDevice.current.batteryLevel

        scheduleMinuteTimer()

        // Pil sadece bildirimle güncellenir (polling yok).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        // Arka plandan dönünce timer'lar gecikmiş olabilir: saati/pili hemen tazele.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Saat dakikada bir değişir: timer tam dakika başında, 60 sn'de bir tetiklenir.
    private func scheduleMinuteTimer() {
        timer?.invalidate()
        now = Date()
        let nextMinute = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)
        let t = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func didBecomeActive() {
        batteryLevel = UIDevice.current.batteryLevel
        scheduleMinuteTimer()
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func batteryChanged() {
        batteryLevel = UIDevice.current.batteryLevel
    }

    var timeString: String {
        Self.timeFormatter.string(from: now)
    }

    var dateString: String {
        Self.dateFormatter.string(from: now)
    }

    var batteryText: String {
        guard batteryLevel >= 0 else { return "—" }
        return Double(batteryLevel).formatted(.percent.precision(.fractionLength(0)))
    }
}
