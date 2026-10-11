import Foundation
import UIKit
import Combine

/// Saat / tarih / pil için hafif store.
/// UIDevice.isBatteryMonitoringEnabled = true gerekir (init'te açılır).
final class TelemetryStore: ObservableObject {
    @Published var now = Date()
    @Published var batteryLevel: Float = UIDevice.current.batteryLevel
    @Published var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: "keepScreenOn")
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        }
    }

    private var timer: Timer?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.keepScreenOn = UserDefaults.standard.object(forKey: "keepScreenOn") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "keepScreenOn")

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.now = Date()
            self?.batteryLevel = UIDevice.current.batteryLevel
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func batteryChanged() {
        batteryLevel = UIDevice.current.batteryLevel
    }

    var timeString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }

    var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM EEE"
        return f.string(from: now)
    }

    var batteryText: String {
        guard batteryLevel >= 0 else { return "—" }
        return "%\(Int(batteryLevel * 100))"
    }
}
