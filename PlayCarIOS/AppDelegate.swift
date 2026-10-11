import UIKit

/// Yatay (landscape) kilit + karanlık sürüş UI için AppDelegate.
/// Info.plist'te UISupportedInterfaceOrientations zaten sadece landscape.
/// Bu delegate, portrait'e dönüşü sistem seviyesinde engeller.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}
