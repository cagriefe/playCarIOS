import Foundation

/// Uygulamayla gelen "PlayCar DND" kestirmesiyle haberleşme.
/// Kestirme "on" / "off" metniyle Rahatsız Etme'yi açar / kapatır; Kestirmeler
/// x-callback-url ile çalıştırır ve sonucu `playcar://dnd/…` ile geri bildirir.
enum FocusShortcut {
    /// Kestirmeler'deki adı = paketteki dosya adı (tools/make-dnd-shortcut.py).
    static let name = "PlayCar DND"
    static let callbackScheme = "playcar"

    enum Callback: Equatable {
        case on
        case off
        case cancel
        /// Kestirme yok / çalışmadı (Kestirmeler `errorMessage` ekler).
        case error(String?)
    }

    static func runURL(turnOn: Bool) -> URL {
        let state = turnOn ? "on" : "off"
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: state),
            URLQueryItem(name: "x-success", value: "\(callbackScheme)://dnd/\(state)"),
            URLQueryItem(name: "x-cancel", value: "\(callbackScheme)://dnd/cancel"),
            URLQueryItem(name: "x-error", value: "\(callbackScheme)://dnd/error"),
        ]
        guard let url = components.url else { preconditionFailure("invalid shortcut URL") }
        return url
    }

    static func parse(_ url: URL) -> Callback? {
        guard url.scheme == callbackScheme, url.host == "dnd" else { return nil }
        switch url.path {
        case "/on": return .on
        case "/off": return .off
        case "/cancel": return .cancel
        case "/error":
            let message = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "errorMessage" }?.value
            return .error(message)
        default: return nil
        }
    }
}
