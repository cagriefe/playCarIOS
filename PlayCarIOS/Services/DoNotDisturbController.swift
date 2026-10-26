import UIKit
import Combine

/// Rahatsız Etme butonu.
/// iOS, uygulamaların Odak modunu değiştirmesine izin vermez; bu yüzden
/// uygulamayla gelen hazır "PlayCar DND" kestirmesi Kestirmeler üzerinden
/// çalıştırılır (yarım saniye Kestirmeler görünür, sonra PlayCar'a dönülür).
/// İlk kullanımda kestirme bir kez Kestirmeler'e eklenir ("Kestirme Ekle" onayı).
@MainActor
final class DoNotDisturbController: NSObject, ObservableObject {
    /// Son bilinen durum. Kontrol Merkezi'nden değiştirilirse uygulama bilemez;
    /// uzun basma menüsünden açık / kapalı doğrudan seçilebilir.
    @Published private(set) var isOn: Bool {
        didSet { defaults.set(isOn, forKey: Keys.isOn) }
    }
    @Published var showSetup = false
    /// Kestirme çalıştırılamadı (eklenmemiş / silinmiş).
    @Published private(set) var shortcutMissing = false

    private enum Keys {
        static let isOn = "dndOn"
        static let installed = "dndShortcutInstalled"
    }

    private let defaults: UserDefaults
    private var installed: Bool {
        didSet { defaults.set(installed, forKey: Keys.installed) }
    }
    /// Kurulumdan dönünce uygulanacak durum.
    private var pending: Bool?
    private var awaitingInstallReturn = false
    /// Kestirmeler'e gerçekten geçildi mi (menü kapanırken gelen kısa
    /// "aktif" olayları kurulum dönüşü sayılmasın).
    private var leftAppForInstall = false
    private var documentController: UIDocumentInteractionController?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.bool(forKey: Keys.isOn)
        installed = defaults.bool(forKey: Keys.installed)
        super.init()
    }

    func toggle() {
        set(!isOn)
    }

    func set(_ on: Bool) {
        guard installed else {
            pending = on
            shortcutMissing = false
            showSetup = true
            return
        }
        UIApplication.shared.open(FocusShortcut.runURL(turnOn: on)) { [weak self] opened in
            // Kestirmeler uygulaması silinmişse açılamaz.
            if !opened { self?.showMissing() }
        }
    }

    /// `playcar://dnd/…` geri dönüşü.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let callback = FocusShortcut.parse(url) else { return false }
        switch callback {
        case .on:
            isOn = true
            installed = true
        case .off:
            isOn = false
            installed = true
        case .cancel:
            break
        case .error:
            showMissing()
        }
        return true
    }

    /// Hazır kestirmeyi Kestirmeler'e gönder; kullanıcı "Kestirme Ekle"ye dokunur.
    func installShortcut() {
        guard let url = Bundle.main.url(forResource: FocusShortcut.name, withExtension: "shortcut"),
              let presenter = UIApplication.topViewController() else { return }
        let controller = UIDocumentInteractionController(url: url)
        controller.delegate = self
        documentController = controller
        let shown = controller.presentOpenInMenu(from: presenter.view.bounds, in: presenter.view, animated: true)
        if !shown {
            // "Aç" menüsü yoksa paylaşım sayfası (Kestirmeler oradan seçilir).
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = presenter.view
            share.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                if completed { self?.didSendToShortcuts() }
            }
            presenter.present(share, animated: true)
        }
    }

    func appDidEnterBackground() {
        if awaitingInstallReturn { leftAppForInstall = true }
    }

    /// Kestirmeler'den PlayCar'a dönüldü: bekleyen isteği uygula.
    func appDidBecomeActive() {
        guard awaitingInstallReturn, leftAppForInstall else { return }
        awaitingInstallReturn = false
        leftAppForInstall = false
        showSetup = false
        if let pending {
            self.pending = nil
            set(pending)
        }
    }

    private func didSendToShortcuts() {
        // İyimser: dönüşte çalıştırılır; eklenmediyse x-error kurulumu yeniden açar.
        installed = true
        awaitingInstallReturn = true
        leftAppForInstall = false
    }

    private func showMissing() {
        installed = false
        shortcutMissing = true
        showSetup = true
    }
}

// UIKit bu geri çağrıları ana iş parçacığında yapar.
extension DoNotDisturbController: UIDocumentInteractionControllerDelegate {
    nonisolated func documentInteractionController(_ controller: UIDocumentInteractionController,
                                                   willBeginSendingToApplication application: String?) {
        MainActor.assumeIsolated { didSendToShortcuts() }
    }

    nonisolated func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        MainActor.assumeIsolated {
            if !awaitingInstallReturn { documentController = nil }
        }
    }
}

extension UIApplication {
    /// En üstteki view controller (sheet açıksa onun içi).
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
