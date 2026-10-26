import SwiftUI
import AVKit

/// Ses çıkışı seçici (sistem): araç Bluetooth'u, telefon hoparlörü, AirPlay.
/// Uygulamalar sistem sesini değiştiremez; çıkış seçimi bu standart düğmeyle yapılır.
struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor.white.withAlphaComponent(0.85)
        view.activeTintColor = .systemGreen
        view.backgroundColor = .clear
        view.accessibilityLabel = String(localized: "Audio output")
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
