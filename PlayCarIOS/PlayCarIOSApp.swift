import SwiftUI

@main
struct PlayCarIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
                .onAppear {
                    // Sürüş sırasında ekranın kararmasını engelle.
                    // Ayarlardan kapatılabilir olmalı (App Store / pil politikası için).
                    // Bkz: TelemetryBarView -> ekran kilidi toggle'ı.
                    if UserDefaults.standard.object(forKey: "keepScreenOn") == nil {
                        UserDefaults.standard.set(true, forKey: "keepScreenOn")
                    }
                    UIApplication.shared.isIdleTimerDisabled =
                        UserDefaults.standard.bool(forKey: "keepScreenOn")
                }
        }
    }
}
