import SwiftUI

@main
struct PlayCarIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // MapKit rota talimatlarını ve arama sonuçlarını uygulamanın dilinde
        // döndürür. iPhone İngilizce olsa da navigasyon Türkçe konuşsun diye
        // uygulamanın dili Türkçe'ye sabitlenir (sadece bu uygulama etkilenir).
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
        if languages.first?.hasPrefix("tr") != true {
            UserDefaults.standard.set(["tr-TR"] + languages.filter { !$0.hasPrefix("tr") }, forKey: "AppleLanguages")
        }
    }

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
