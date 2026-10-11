import SwiftUI
import MediaPlayer
import AVKit

/// Medya kontrol widget'ı.
/// Ses: custom Slider YOK -> MPVolumeView (sistem sesi + AirPlay).
struct MediaControlView: View {
    @ObservedObject var player: MusicPlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEDYA")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if player.authState != .authorized {
                Button("Müzik Erişimine İzin Ver") {
                    player.requestAuthorization()
                }
                .buttonStyle(.borderedProminent)
                .font(.subheadline.bold())
                Text("Parça bilgisi ve kontrol için medya arşivi izni gerekir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    artworkView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(player.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack(spacing: 16) {
                    Spacer()
                    mediaButton(icon: "backward.fill") { player.previous() }
                    mediaButton(icon: player.isPlaying ? "pause.fill" : "play.fill", big: true) {
                        player.togglePlayPause()
                    }
                    mediaButton(icon: "forward.fill") { player.next() }
                    Spacer()
                }

                // Sistem sesi + AirPlay (doğru yöntem)
                HStack(spacing: 8) {
                    SystemVolumeView()
                    AirPlayButtonView()
                        .frame(width: 32, height: 32)
                }
                .frame(height: 32)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { if player.authState == .notDetermined { player.requestAuthorization() } }
    }

    private var artworkView: some View {
        Group {
            if let img = player.artwork {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1))
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func mediaButton(icon: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: big ? 28 : 22, weight: .semibold))
                .frame(width: big ? 68 : 56, height: big ? 68 : 56)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
        // Sürüş için büyük dokunma hedefi (min 44pt, burada 56-68pt)
    }
}

/// Sistem ses slider'ı (MPVolumeView). Custom Slider ile sistem sesi
/// değiştirilemez; bu Apple'ın bu iş için verdiği tek view'dır.
struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView(frame: .zero)
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// AirPlay / çıkış rotası butonu. MPVolumeView.showsRouteButton
/// iOS 13'ten beri deprecated; yerine AVRoutePickerView kullanılır.
struct AirPlayButtonView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(frame: .zero)
        v.activeTintColor = .systemOrange
        v.tintColor = .white
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
