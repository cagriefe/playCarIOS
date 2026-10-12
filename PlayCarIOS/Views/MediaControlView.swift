import SwiftUI
import MediaPlayer

/// Sağ panel içi görünüm yönlendirici (haritayı kapatmaz, sheet yok).
enum MediaPanelState: Equatable {
    case nowPlaying
    case playlists
    case tracks
}

/// CarPlay "Şimdi Çalınıyor" kartı + panel içi liste gezinmesi:
/// parça -> listeler -> parçalar. Geri butonları her başlıkta.
struct MediaControlView: View {
    @ObservedObject var player: MusicPlayerManager
    @State private var panelState: MediaPanelState = .nowPlaying
    @State private var selectedPlaylist: MPMediaPlaylist?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch panelState {
            case .nowPlaying:
                nowPlayingView
            case .playlists:
                playlistsView
            case .tracks:
                tracksView
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: panelState)
        .onAppear { if player.authState == .notDetermined { player.requestAuthorization() } }
    }

    // MARK: - Şimdi çalınıyor

    private var nowPlayingView: some View {
        Group {
            HStack(spacing: 6) {
                Text("MEDYA")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    player.loadPlaylists()
                    panelState = .playlists
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
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 10) {
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

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.12))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.7))
                            .frame(width: geo.size.width * player.progress)
                    }
                }
                .frame(height: 3)

                Spacer(minLength: 8)

                HStack(spacing: 14) {
                    Spacer(minLength: 0)
                    mediaButton(icon: "backward.fill", size: 50) { player.previous() }
                    mediaButton(icon: player.isPlaying ? "pause.fill" : "play.fill", size: 64) {
                        player.togglePlayPause()
                    }
                    mediaButton(icon: "forward.fill", size: 50) { player.next() }
                    Spacer(minLength: 0)
                }
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - Çalma listeleri

    private var playlistsView: some View {
        Group {
            panelHeader(title: "Çalma Listeleri") { panelState = .nowPlaying }

            if player.playlists.isEmpty {
                Text("Liste bulunamadı. Müzik uygulamasında liste oluşturun.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(player.playlists, id: \.persistentID) { list in
                            Button {
                                selectedPlaylist = list
                                player.loadTracks(for: list)
                                panelState = .tracks
                            } label: {
                                HStack(spacing: 10) {
                                    playlistArtwork(for: list)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(list.name ?? "İsimsiz liste")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("\(list.count) parça")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 7)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .frame(minHeight: 54)
                        }
                    }
                }
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - Parçalar

    private var tracksView: some View {
        Group {
            panelHeader(title: selectedPlaylist?.name ?? "Parçalar") {
                panelState = .playlists
            }

            sortMenu

            if player.currentTracks.isEmpty {
                Text("Bu listede parça yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(player.currentTracks.enumerated()), id: \.element.persistentID) { index, item in
                            Button {
                                if let list = selectedPlaylist {
                                    player.playTrack(item, in: list)
                                }
                                panelState = .nowPlaying
                            } label: {
                                HStack(spacing: 10) {
                                    if item.persistentID == player.nowPlayingID {
                                        Image(systemName: "waveform")
                                            .font(.body)
                                            .foregroundStyle(.green)
                                            .frame(width: 22)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                            .frame(width: 22)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title ?? "Bilinmeyen parça")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(item.artist ?? "Bilinmeyen sanatçı")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text(TrackFormat.duration(item.playbackDuration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 7)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .frame(minHeight: 52)
                        }
                    }
                }
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - Ortak parçalar

    /// Her başlıkta kalıcı, büyük Geri butonu.
    private func panelHeader(title: String, onBack: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                    Text("Geri")
                        .font(.subheadline.bold())
                }
                .frame(minWidth: 64, minHeight: 36)
            }
            Text(title)
                .font(.subheadline.bold())
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(MusicPlayerManager.TrackSort.allCases, id: \.self) { sort in
                Button { player.setSort(sort) } label: {
                    if player.trackSort == sort {
                        Label(sort.title, systemImage: "checkmark")
                    } else {
                        Text(sort.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2.bold())
                Text("Sırala: \(player.trackSort.shortTitle)")
                    .font(.caption2.bold())
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
        }
    }

    private func playlistArtwork(for list: MPMediaPlaylist) -> some View {
        Group {
            if let art = list.items.first?.artwork?.image(at: CGSize(width: 80, height: 80)) {
                Image(uiImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1))
                    Image(systemName: "music.note.list")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

// MARK: - Format

enum TrackFormat {
    /// 184 sn -> "3:04"
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
