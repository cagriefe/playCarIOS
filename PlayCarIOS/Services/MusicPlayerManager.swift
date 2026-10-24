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
    @Published var elapsed: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    /// Parmak bardayken ilerleme sayacı duraklatılır (çekişme olmasın).
    var scrubbing = false
    @Published var nowPlayingID: UInt64 = 0
    @Published var currentTracks: [MPMediaItem] = []
    @Published var currentPlaylist: MPMediaPlaylist?
    @Published var trackSort: TrackSort = .dateAddedDesc
    @Published var lastError: String?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?
    /// Artwork yeniden decode'u engelle: aynı parça tekrar gelirse atla.
    private var artworkCacheID: UInt64 = 0
    private var playlistArtworkCache: [UInt64: UIImage?] = [:]

    init() {
        syncAuthState()
        if authState == .authorized {
            beginObserving()
        }
        // Timer artık isteğe bağlı: sadece çalarken kurulur (pil).
        if isPlaying { ensureProgressTimer() }
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

    /// Apple Music davranışı: 3 sn'den fazla çalındıysa parçayı başa sarar,
    /// değilse önceki parçaya geçer.
    func previous() {
        guard authState == .authorized else { return }
        if player.currentPlaybackTime > 3 {
            player.skipToBeginning()
            updateProgress()
        } else {
            player.skipToPreviousItem()
        }
    }

    /// Liste kapağı (önbellekli): satır her çizildiğinde yeniden decode edilmez.
    func artwork(for playlist: MPMediaPlaylist) -> UIImage? {
        let key = playlist.persistentID
        if let cached = playlistArtworkCache[key] { return cached }
        let image = playlist.representativeItem?.artwork?.image(at: CGSize(width: 80, height: 80))
            ?? playlist.items.first?.artwork?.image(at: CGSize(width: 80, height: 80))
        playlistArtworkCache[key] = image
        return image
    }

    /// Kullanıcının çalma listeleri (Müzik arşivi).
    /// Sorgu arka planda yapılır, liste sıralaması orada biter (UI takılmaz).
    func loadPlaylists() {
        guard authState == .authorized else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let lists = MPMediaQuery.playlists().collections?.compactMap { $0 as? MPMediaPlaylist } ?? []
            let sorted = lists.sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
            DispatchQueue.main.async { self?.playlists = sorted }
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
        sortTracks(of: playlist, by: trackSort)
    }

    /// Sıralamayı değiştirir, yüklü listeyi yeniden dizer.
    func setSort(_ sort: TrackSort) {
        trackSort = sort
        guard let list = currentPlaylist else { return }
        sortTracks(of: list, by: sort)
    }

    /// Arka planda sırala; bu arada başka liste/sıralama seçildiyse eski sonucu at.
    private func sortTracks(of playlist: MPMediaPlaylist, by sort: TrackSort) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ordered = Self.applySort(playlist.items, by: sort)
            DispatchQueue.main.async {
                guard let self,
                      self.currentPlaylist?.persistentID == playlist.persistentID,
                      self.trackSort == sort else { return }
                self.currentTracks = ordered
            }
        }
    }

    /// İleri/geri sar: 0...1 oranını süreye çevirir.
    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        let time = clamped * duration
        player.currentPlaybackTime = time
        elapsed = time
        progress = clamped
    }

    /// Seçilen parçadan başlayarak, ekranda görünen sırayla çalar
    /// (sıralama "İsim" ise sonraki parça da isim sırasına göre gelir).
    func playTrack(at index: Int) {
        guard authState == .authorized, currentTracks.indices.contains(index) else { return }
        player.setQueue(with: MPMediaItemCollection(items: currentTracks))
        player.nowPlayingItem = currentTracks[index]
        player.play()
        refreshNowPlaying()
    }

    /// Varsayılan: eklenme tarihi azalan (Apple Music davranışı).
    private static func applySort(_ items: [MPMediaItem], by sort: TrackSort) -> [MPMediaItem] {
        switch sort {
        case .dateAddedDesc:
            return items.sorted {
                $0.dateAdded > $1.dateAdded
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
        let playing = (player.playbackState == .playing)
        isPlaying = playing
        // İlerleme sayacı sadece çalarken yaşar (duraklatınca timer ölür).
        if playing {
            ensureProgressTimer()
        } else {
            progressTimer?.invalidate()
            progressTimer = nil
        }
    }

    /// Parça ilerlemesi (0...1). Sistem çalardan 1 sn'de bir okunur, toleranslı.
    /// Sadece çalma sırasında aktif — duraklatınca kurulmaz.
    private func ensureProgressTimer() {
        guard progressTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying, !self.scrubbing else { return }
            self.updateProgress()
        }
        t.tolerance = 0.25
        progressTimer = t
    }

    private func updateProgress() {
        guard let item = player.nowPlayingItem, item.playbackDuration > 0 else {
            progress = 0
            elapsed = 0
            duration = 0
            return
        }
        duration = item.playbackDuration
        elapsed = player.currentPlaybackTime
        progress = min(max(player.currentPlaybackTime / item.playbackDuration, 0), 1)
    }

    private func refreshNowPlaying() {
        refreshPlaybackState()
        updateProgress()
        let pid = player.nowPlayingItem?.persistentID ?? 0
        // Aynı parçaysa artwork'ü yeniden decode etme (CPU/pil).
        let sameTrack = (pid == nowPlayingID && pid != 0)
        nowPlayingID = pid
        guard let item = player.nowPlayingItem else {
            title = "Çalan parça yok"
            artist = "Müzik uygulamasında başlatın"
            artwork = nil
            artworkCacheID = 0
            return
        }
        title = item.title ?? "Bilinmeyen parça"
        artist = item.artist ?? "Bilinmeyen sanatçı"
        if sameTrack && pid == artworkCacheID {
            return
        }
        // Bulut parçalarda kapak geç gelebilir: bulunamadıysa önbelleğe alma,
        // sonraki bildirimde tekrar denensin.
        if let image = item.artwork?.image(at: CGSize(width: 144, height: 144)) {
            artwork = image
            artworkCacheID = pid
        } else {
            artwork = nil
            artworkCacheID = 0
        }
    }
}
