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
    /// Arama varken kart arama görünümüne geçer (liste durumu korunur).
    @ObservedObject var calls: CallStore
    @State private var panelState: MediaPanelState = .nowPlaying
    @State private var selectedPlaylist: MPMediaPlaylist?
    /// Parmak bardayken görünen geçici oran (bırakınca çalara işlenir).
    @State private var scrubFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsCall {
                CallPanelView(calls: calls)
            } else {
                switch panelState {
                case .nowPlaying:
                    nowPlayingView
                case .playlists:
                    playlistsView
                case .tracks:
                    tracksView
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(showsCall ? 0.6 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.2), value: panelState)
        .animation(.easeInOut(duration: 0.25), value: showsCall)
        .onAppear { if player.authState == .notDetermined { player.requestAuthorization() } }
    }

    private var showsCall: Bool {
        calls.inCall && !calls.dismissed
    }

    // MARK: - Şimdi çalınıyor

    /// Sağ üst köşe: arama gizlenmişse yeşil süre hapı, değilse Listeler.
    @ViewBuilder
    private var cornerButton: some View {
        if calls.inCall {
            Button { calls.show() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "phone.fill")
                    Text(calls.phase == .active || calls.phase == .onHold ? calls.elapsedText : String(localized: "Call"))
                        .monospacedDigit()
                }
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.green, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                player.loadPlaylists()
                panelState = .playlists
            } label: {
                Image(systemName: "music.note.list")
                    .font(.subheadline.bold())
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Playlists")
        }
    }

    private var nowPlayingView: some View {
        VStack(spacing: 6) {
            if player.authState != .authorized {
                HStack {
                    Text("MEDIA")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    cornerButton
                }
                Text("Media access is needed to show track info.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Allow") { player.requestAuthorization() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer(minLength: 0)
            } else {
                // 1. Parça bilgisi
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
                    cornerButton
                }

                Spacer(minLength: 2)

                // 2. Ortalanmış ilerleme bölümü (bar üstte, süreler altta)
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: geo.size.width * displayFraction)
                        }
                        .frame(height: 6)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Sürüklerken çalara HER karede seek gönderme (IPC + pil).
                                    // Parmak görünümü yerelde güncellenir, tek seek bırakınca yapılır.
                                    let f = min(max(value.location.x / geo.size.width, 0), 1)
                                    scrubFraction = f
                                    player.scrubbing = true
                                }
                                .onEnded { value in
                                    let f = min(max(value.location.x / geo.size.width, 0), 1)
                                    player.seek(to: f)
                                    scrubFraction = nil
                                    player.scrubbing = false
                                }
                        )
                    }
                    .frame(height: 18)
                    HStack {
                        Text(TrackFormat.duration(displayElapsed))
                        Spacer()
                        Text("-\(TrackFormat.duration(max(player.duration - displayElapsed, 0)))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }

                Spacer(minLength: 2)

                // 3. Kontroller (taşmayı önlemek için kompakt: 46/42)
                // Solda ses çıkışı (Bluetooth / hoparlör / AirPlay); sağdaki boşluk
                // çalma düğmelerini ortada tutar.
                HStack(spacing: 0) {
                    AudioRoutePicker()
                        .frame(width: 34, height: 34)
                    Spacer(minLength: 4)
                    HStack(spacing: 18) {
                        mediaButton(icon: "backward.fill", size: 42) { player.previous() }
                        mediaButton(icon: player.isPlaying ? "pause.fill" : "play.fill", size: 46) {
                            player.togglePlayPause()
                        }
                        mediaButton(icon: "forward.fill", size: 42) { player.next() }
                    }
                    Spacer(minLength: 4)
                    Color.clear
                        .frame(width: 34, height: 34)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    /// Ekranda görünen oran/süre: sürükleme varsa parmak, yoksa çalar.
    private var displayFraction: Double {
        scrubFraction ?? player.progress
    }

    private var displayElapsed: TimeInterval {
        displayFraction * player.duration
    }

    // MARK: - Çalma listeleri

    private var playlistsView: some View {
        Group {
            panelHeader(title: String(localized: "Playlists")) { panelState = .nowPlaying }

            if player.playlists.isEmpty {
                Text("No playlists found. Create one in the Music app.")
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
                                        Text(list.name ?? String(localized: "Untitled Playlist"))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("\(list.count) tracks")
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
                            .buttonStyle(.plain)
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
            panelHeader(title: selectedPlaylist?.name ?? String(localized: "Tracks")) {
                panelState = .playlists
            }

            sortMenu

            if player.currentTracks.isEmpty {
                Text("This playlist is empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        // id: sıra — aynı parça listede iki kez olabilir (persistentID çakışır).
                        ForEach(Array(player.currentTracks.enumerated()), id: \.offset) { index, item in
                            Button {
                                player.playTrack(at: index)
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
                                        Text(item.title ?? String(localized: "Unknown Track"))
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(item.artist ?? String(localized: "Unknown Artist"))
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
                            .buttonStyle(.plain)
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
                    Text("Back")
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
                Text("Sort: \(player.trackSort.shortTitle)")
                    .font(.caption2.bold())
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
        }
    }

    private func playlistArtwork(for list: MPMediaPlaylist) -> some View {
        Group {
            if let art = player.artwork(for: list) {
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
        .frame(width: 44, height: 44)
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
