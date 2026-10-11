import SwiftUI
import MediaPlayer
import AVKit

/// Kompakt medya widget'ı: bilgi satırı + kontrol satırı + ses satırı.
/// Dar panele taşmadan sığar; tüm metinler lineLimit(1).
struct MediaControlView: View {
    @ObservedObject var player: MusicPlayerManager
    @State private var showPlaylists = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("MEDYA")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    player.loadPlaylists()
                    showPlaylists = true
                } label: {
                    Label("Listeler", systemImage: "music.note.list")
                        .font(.caption2.bold())
                }
            }

            if player.authState != .authorized {
                Text("Parça bilgisi için medya izni gerekir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("İzin Ver") { player.requestAuthorization() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    artworkView
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text(player.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    mediaButton(icon: "backward.fill", size: 48) { player.previous() }
                    mediaButton(icon: player.isPlaying ? "pause.fill" : "play.fill", size: 60) {
                        player.togglePlayPause()
                    }
                    mediaButton(icon: "forward.fill", size: 48) { player.next() }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    SystemVolumeView()
                    AirPlayButtonView()
                        .frame(width: 30, height: 30)
                }
                .frame(height: 28)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { if player.authState == .notDetermined { player.requestAuthorization() } }
        .sheet(isPresented: $showPlaylists) {
            PlaylistsSheetView(player: player)
        }
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
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func mediaButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
    }
}

/// Çalma listeleri sayfası: dokun → sıraya koy + çal.
struct PlaylistsSheetView: View {
    @ObservedObject var player: MusicPlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if player.playlists.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Liste bulunamadı")
                            .font(.headline)
                        Text("Müzik uygulamasında bir çalma listesi oluşturun.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(player.playlists, id: \.persistentID) { list in
                        Button {
                            player.playPlaylist(list)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(list.name ?? "İsimsiz liste")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(list.count) parça")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Listelerim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .onAppear { player.loadPlaylists() }
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
