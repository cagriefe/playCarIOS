import SwiftUI

@main
struct PlayCarIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
                .onAppear {
                    // Araç ekranı: PlayCar açıkken ekran hiç kararmaz. iOS bunu
                    // sadece uygulama öndeyken uygular; çıkınca telefon normale döner.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
