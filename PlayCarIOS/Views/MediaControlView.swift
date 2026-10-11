import SwiftUI
import MediaPlayer

/// CarPlay "Şimdi Çalınıyor" kartı: kapak + başlık/sanatçı + kontroller.
/// CarPlay'de ekranda ses kontrolü olmaz (araba düğmesi kullanır),
/// bu yüzden slider yok — kart ince ve sığar.
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
                    mediaButton(icon: "backward.fill", size: 46) { player.previous() }
                    mediaButton(icon: player.isPlaying ? "pause.fill" : "play.fill", size: 58) {
                        player.togglePlayPause()
                    }
                    mediaButton(icon: "forward.fill", size: 46) { player.next() }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
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
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func mediaButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.14))
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
