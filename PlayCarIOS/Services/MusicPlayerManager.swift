import Foundation
import MediaPlayer
import UIKit
import Combine

/// Apple Music / Medya Arşivi kontrolü.
/// DÜZELTME NOTU (proposal fix):
/// - Proposal hem MusicKit hem MPMusicPlayerController diyordu. Kafa karışıklığı yaratır.
///   Bu sürüm sadece MediaPlayer kullanır: sistem çaları yönetir, ek MusicKit entitlement gerekmez.
/// - Ses seviyesi için custom Slider KULLANILMAZ. iOS'ta sistem sesini Slider ile
///   değiştirmek (player.volume) deprecated ve App Store'da çalışmaz.
///   Doğrusu MPVolumeView (sistem ses + AirPlay rotası) kullanmaktır.
final class MusicPlayerManager: ObservableObject {

    enum AuthState: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    /// Parça sıralaması (Türkçe etiketli).
    enum TrackSort: String, CaseIterable {
        case dateAddedDesc
        case titleAZ
        case artistAZ

        var title: String {
            switch self {
            case .dateAddedDesc: return "Eklenme Tarihi (Yeniler)"
            case .titleAZ: return "İsim (A-Z)"
            case .artistAZ: return "Sanatçı (A-Z)"
            }
        }

        var shortTitle: String {
            switch self {
            case .dateAddedDesc: return "Tarih"
            case .titleAZ: return "İsim"
            case .artistAZ: return "Sanatçı"
            }
        }
    }

    @Published var authState: AuthState = .notDetermined
    @Published var isPlaying: Bool = false
    @Published var title: String = "Çalan parça yok"
    @Published var artist: String = "—"
    @Published var artwork: UIImage?
    @Published var playlists: [MPMediaPlaylist] = []
    @Published var progress: Double = 0
    @Published var nowPlayingID: UInt64 = 0
    @Published var currentTracks: [MPMediaItem] = []
    @Published var currentPlaylist: MPMediaPlaylist?
    @Published var trackSort: TrackSort = .dateAddedDesc
    @Published var lastError: String?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?

    init() {
        syncAuthState()
        if authState == .authorized {
            beginObserving()
        }
        startProgressTimer()
    }

    deinit {
        endObserving()
        progressTimer?.invalidate()
    }

    func requestAuthorization() {
        lastError = nil
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.authState = .authorized
                    self?.beginObserving()
                case .denied, .restricted:
                    self?.authState = .denied
                case .notDetermined:
                    self?.authState = .notDetermined
                @unknown default:
                    self?.authState = .notDetermined
                }
            }
        }
    }

    func togglePlayPause() {
        guard authState == .authorized else { requestAuthorization(); return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func next() {
        guard authState == .authorized else { return }
        player.skipToNextItem()
    }

    func previous() {
        guard authState == .authorized else { return }
        player.skipToPreviousItem()
    }

    /// Kullanıcının çalma listeleri (Müzik arşivi).
    func loadPlaylists() {
        guard authState == .authorized else { return }
        let lists = MPMediaQuery.playlists().collections?.compactMap { $0 as? MPMediaPlaylist } ?? []
        playlists = lists.sorted {
            ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
    }

    /// Listeyi sıraya koyup çalmaya başlar.
    /// MPMediaPlaylist bir MPMediaItemCollection'dır, doğrudan queue olur.
    func playPlaylist(_ playlist: MPMediaPlaylist) {
        guard authState == .authorized else { return }
        player.setQueue(with: playlist)
        player.play()
        refreshNowPlaying()
    }

    /// Seçili listenin parçalarını asenkron yükler + mevcut sıralamayı uygular.
    func loadTracks(for playlist: MPMediaPlaylist) {
        guard authState == .authorized else { return }
        currentPlaylist = playlist
        currentTracks = []
        let sort = trackSort
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = playlist.items
            guard let self else { return }
            let ordered = self.applySort(items, by: sort)
            DispatchQueue.main.async { self.currentTracks = ordered }
        }
    }

    /// Sıralamayı değiştirir, yüklü listeyi yeniden dizer.
    func setSort(_ sort: TrackSort) {
        trackSort = sort
        guard let list = currentPlaylist else { return }
        currentTracks = applySort(list.items, by: sort)
    }

    /// Tek parçayı çal: listeyi sıraya koy, ilgili parçadan başlat.
    func playTrack(_ item: MPMediaItem, in playlist: MPMediaPlaylist) {
        guard authState == .authorized else { return }
        player.setQueue(with: playlist)
        player.nowPlayingItem = item
        player.play()
        refreshNowPlaying()
    }

    /// Varsayılan: eklenme tarihi azalan (Apple Music davranışı).
    /// Tarihi eksik parçalar en alta düşer, liste bozulmaz.
    private func applySort(_ items: [MPMediaItem], by sort: TrackSort) -> [MPMediaItem] {
        switch sort {
        case .dateAddedDesc:
            return items.sorted {
                ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast)
            }
        case .titleAZ:
            return items.sorted {
                ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending
            }
        case .artistAZ:
            return items.sorted {
                ($0.artist ?? "").localizedCaseInsensitiveCompare($1.artist ?? "") == .orderedAscending
            }
        }
    }

    // MARK: - Private

    private func syncAuthState() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: authState = .authorized
        case .denied, .restricted: authState = .denied
        case .notDetermined: authState = .notDetermined
        @unknown default: authState = .notDetermined
        }
        refreshNowPlaying()
    }

    private func beginObserving() {
        player.beginGeneratingPlaybackNotifications()
        refreshNowPlaying()
        loadPlaylists()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNowPlayingChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
    }

    private func endObserving() {
        NotificationCenter.default.removeObserver(self)
        player.endGeneratingPlaybackNotifications()
    }

    @objc private func handleNowPlayingChanged() {
        DispatchQueue.main.async { [weak self] in self?.refreshNowPlaying() }
    }

    @objc private func handlePlaybackStateChanged() {
        DispatchQueue.main.async { [weak self] in self?.refreshPlaybackState() }
    }

    private func refreshPlaybackState() {
        isPlaying = (player.playbackState == .playing)
    }

    /// Parça ilerlemesi (0...1). Sistem çalardan 1 sn'de bir okunur.
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.updateProgress()
        }
    }

    private func updateProgress() {
        guard let item = player.nowPlayingItem, item.playbackDuration > 0 else {
            progress = 0
            return
        }
        progress = min(max(player.currentPlaybackTime / item.playbackDuration, 0), 1)
    }

    private func refreshNowPlaying() {
        refreshPlaybackState()
        updateProgress()
        nowPlayingID = player.nowPlayingItem?.persistentID ?? 0
        guard let item = player.nowPlayingItem else {
            title = "Çalan parça yok"
            artist = "Müzik uygulamasında başlatın"
            artwork = nil
            return
        }
        title = item.title ?? "Bilinmeyen parça"
        artist = item.artist ?? "Bilinmeyen sanatçı"
        if let art = item.artwork {
            artwork = art.image(at: CGSize(width: 200, height: 200))
        } else {
            artwork = nil
        }
    }
}
