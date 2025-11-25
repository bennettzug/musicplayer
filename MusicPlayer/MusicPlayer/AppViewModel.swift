import Foundation
import Combine
import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class AppViewModel: ObservableObject {
    @Published var library: [Album] = []
    @Published var currentAlbum: Album?
    @Published var currentTrackIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Double = 0.8
    @Published var isAlbumBrowserOpen: Bool = true
    @Published var isQueueVisible: Bool = true
    @Published var backgroundColor: Color = Color(red: 0.12, green: 0.12, blue: 0.14)
    @Published var artists: [String] = []
    @Published var selectedArtist: String?
    @Published var libraryPath: String?
    @Published var searchText: String = "" {
        didSet {
            collapsedSearchOverrides.removeAll()
        }
    }
    @Published var expandedArtists: Set<String> = []
    @Published var collapsedSearchOverrides: Set<String> = []

    private let player = PlayerController()
    private var cancellables: Set<AnyCancellable> = []
    private var progressTimer: AnyCancellable?
    private let bookmarkKey = "musicplayer.libraryBookmark"
    private let ciContext = CIContext()
    private let lastFMClient = LastFMClient()
    @Published var lastFMUsername: String?
    @Published var lastFMStatus: String = "Not linked"
    private var lastFMSessionKey: String? {
        didSet {
            lastFMUsername = lastFMUsername
        }
    }
    private var pendingLastFMToken: String?

    private var currentTrackStartDate: Date?
    private var removeVolumeListener: (() -> Void)?

    init() {
        if let sysVol = SystemVolume.current() {
            volume = sysVol
        }
        Task { await loadPersistedLibrary() }
        loadLastFMSession()
        startSystemVolumeListener()
        player.onTrackEnd = { [weak self] in
            Task { @MainActor in
                self?.handleTrackFinished()
            }
        }
        player.onExternalPause = { [weak self] in
            Task { @MainActor in
                self?.handleExternalPause()
            }
        }
    }

    func togglePlayback() {
        guard let album = currentAlbum else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if player.hasCurrentItem {
                player.resume()
                isPlaying = true
                startProgressTimer()
            } else {
                play(album: album, trackIndex: currentTrackIndex)
            }
        }
    }

    func play(album: Album, trackIndex: Int = 0) {
        scrobbleIfNeeded()
        currentAlbum = album
        currentTrackIndex = trackIndex
        playbackPosition = 0
        duration = album.tracks[safe: trackIndex]?.duration ?? 0
        isPlaying = true
        updatePalette(from: album)
        currentTrackStartDate = Date()
        sendLastFMNowPlaying(track: album.tracks[trackIndex], album: album)
        player.play(track: album.tracks[trackIndex], volume: 1.0)
        startProgressTimer()
    }

    func playNext(autoAdvance: Bool = false) {
        guard let album = currentAlbum else { return }
        if !autoAdvance {
            scrobbleIfNeeded()
        }
        let nextIndex = (currentTrackIndex + 1) % album.tracks.count
        play(album: album, trackIndex: nextIndex)
    }

    func playPrevious() {
        guard let album = currentAlbum else { return }
        let previousIndex = max(currentTrackIndex - 1, 0)
        play(album: album, trackIndex: previousIndex)
    }

    func seek(to time: TimeInterval) {
        playbackPosition = time
        player.seek(to: time)
    }

    func setVolume(_ newVolume: Double) {
        volume = newVolume
        SystemVolume.set(newVolume)
    }

    func toggleAlbumBrowser() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isAlbumBrowserOpen.toggle()
        }
    }

    func rescanLibrary() {
        guard let path = libraryPath else { return }
        Task {
            await loadLibrary(from: URL(fileURLWithPath: path))
        }
    }

    func toggleQueueVisibility() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isQueueVisible.toggle()
        }
    }

    // MARK: - Last.fm

    func startLastFMAuth() {
        Task {
            do {
                let token = try await lastFMClient.beginAuthFlow()
                await MainActor.run {
                    self.pendingLastFMToken = token
                    self.lastFMStatus = "Authorize in browser, then click Complete."
                }
            } catch {
                await MainActor.run {
                    self.lastFMStatus = "Auth failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func completeLastFMAuth() {
        guard let token = pendingLastFMToken else {
            lastFMStatus = "No pending token. Start link again."
            return
        }
        Task {
            do {
                let session = try await lastFMClient.completeAuth(token: token)
                storeLastFMSession(sessionKey: session.key, username: session.username)
                await MainActor.run {
                    self.lastFMUsername = session.username
                    self.lastFMStatus = "Linked as \(session.username)"
                    self.pendingLastFMToken = nil
                }
            } catch {
                await MainActor.run {
                    self.lastFMStatus = "Link failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func unlinkLastFM() {
        deleteLastFMSession()
        lastFMUsername = nil
        lastFMSessionKey = nil
        lastFMStatus = "Not linked"
    }

    func pickAlbumFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Library"
        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
            Task { await loadLibrary(from: url) }
        }
    }

    private func loadLibrary(from url: URL) async {
        do {
            let albums = try await LibraryScanner().scan(url: url)
            await MainActor.run {
                self.library = albums
                self.artists = Array(Set(albums.map { $0.artist.isEmpty ? "Unknown Artist" : $0.artist }))
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                self.selectedArtist = nil
                self.expandedArtists.removeAll()
                self.currentAlbum = nil
                self.isPlaying = false
                self.playbackPosition = 0
                self.duration = 0
                self.libraryPath = url.path
            }
        } catch {
            print("Failed to load album: \(error)")
        }
    }

    private func loadPersistedLibrary() async {
        guard let url = restoreBookmark() else { return }
        await loadLibrary(from: url)
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    private func restoreBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                saveBookmark(for: url)
            }
            if url.startAccessingSecurityScopedResource() {
                libraryPath = url.path
                return url
            }
        } catch {
            print("Failed to restore bookmark: \(error)")
        }
        return nil
    }

    private func startProgressTimer() {
        progressTimer?.cancel()
        progressTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isPlaying else { return }
                self.playbackPosition = self.player.currentTime()
                self.duration = max(self.duration, self.player.currentDuration())
            }
    }

    private func startSystemVolumeListener() {
        removeVolumeListener = SystemVolume.addVolumeChangeListener { [weak self] newValue in
            guard let self else { return }
            Task { @MainActor in
                self.volume = newValue
            }
        }
    }

    private func scrobbleIfNeeded() {
        guard let album = currentAlbum,
              let track = album.tracks[safe: currentTrackIndex],
              let startDate = currentTrackStartDate else { return }

        // Last.fm: track must be > 30s
        guard track.duration > 30 else { return }

        let elapsed = playbackPosition
        let threshold = min(track.duration * 0.5, 240)
        guard elapsed >= threshold else { return }

        guard let sessionKey = lastFMSessionKey else { return }

        Task {
            await lastFMClient.scrobble(sessionKey: sessionKey,
                                        track: track,
                                        album: album,
                                        startDate: startDate)
        }
    }

    private func handleTrackFinished() {
        scrobbleIfNeeded()
        playNext(autoAdvance: true)
    }

    private func handleExternalPause() {
        isPlaying = false
        player.pause()
    }

    private func sendLastFMNowPlaying(track: Track, album: Album) {
        guard let sessionKey = lastFMSessionKey else { return }
        Task {
            await lastFMClient.updateNowPlaying(sessionKey: sessionKey, track: track, album: album)
        }
    }

    private func updatePalette(from album: Album) {
        backgroundColor = dominantColor(from: album.coverData)
    }

    private func dominantColor(from data: Data?) -> Color {
        guard let data, let ciImage = CIImage(data: data) else {
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        }

        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent

        guard let output = filter.outputImage else {
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    func selectArtist(_ artist: String) {
        selectedArtist = artist
    }

    func clearArtistSelection() {
        selectedArtist = nil
    }

    func filteredArtists() -> [String] {
        let base = artists
        guard !searchText.isEmpty else { return base }
        let query = searchText.lowercased()
        return base.filter { $0.lowercased().contains(query) || albumsForArtist($0).contains(where: { $0.title.lowercased().contains(query) }) }
    }

    func albumsForArtist(_ artist: String) -> [Album] {
        library
            .filter { ($0.artist.isEmpty ? "Unknown Artist" : $0.artist) == artist }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func albumsForArtistFiltered(_ artist: String) -> [Album] {
        let albums = albumsForArtist(artist)
        guard !searchText.isEmpty else { return albums }
        let query = searchText.lowercased()
        if artistMatchesQuery(artist) {
            return albums
        }
        return albums.filter { $0.title.lowercased().contains(query) }
    }

    func artistHasAlbumMatch(_ artist: String) -> Bool {
        let query = searchText.lowercased()
        return albumsForArtist(artist).contains { $0.title.lowercased().contains(query) }
    }

    func artistMatchesQuery(_ artist: String) -> Bool {
        let query = searchText.lowercased()
        return artist.lowercased().contains(query)
    }

    func toggleArtistExpansion(_ artist: String, hasSearchMatch: Bool) {
        if expandedArtists.contains(artist) {
            expandedArtists.remove(artist)
        } else if hasSearchMatch {
            // Collapse override for search-driven expansion
            if collapsedSearchOverrides.contains(artist) {
                collapsedSearchOverrides.remove(artist)
            } else {
                collapsedSearchOverrides.insert(artist)
            }
        } else {
            expandedArtists.insert(artist)
        }
    }

    func isArtistExpanded(_ artist: String) -> Bool {
        let hasAlbumMatch = searchText.isEmpty ? false : artistHasAlbumMatch(artist)
        let autoExpand = hasAlbumMatch && !collapsedSearchOverrides.contains(artist)
        return expandedArtists.contains(artist) || autoExpand
    }

    func setArtistExpanded(_ artist: String, _ expanded: Bool) {
        if expanded {
            expandedArtists.insert(artist)
            collapsedSearchOverrides.remove(artist)
        } else {
            expandedArtists.remove(artist)
            if !searchText.isEmpty {
                collapsedSearchOverrides.insert(artist)
            }
        }
    }

    // MARK: - Last.fm persistence

    private func storeLastFMSession(sessionKey: String, username: String) {
        lastFMSessionKey = sessionKey
        lastFMUsername = username
        lastFMStatus = "Linked as \(username)"
        KeychainHelper.save(key: "lastfm_session", value: sessionKey)
        UserDefaults.standard.set(username, forKey: "lastfm_username")
    }

    private func loadLastFMSession() {
        if let session = KeychainHelper.load(key: "lastfm_session") {
            lastFMSessionKey = session
            lastFMUsername = UserDefaults.standard.string(forKey: "lastfm_username")
            if let user = lastFMUsername {
                lastFMStatus = "Linked as \(user)"
            } else {
                lastFMStatus = "Linked"
            }
        }
    }

    private func deleteLastFMSession() {
        KeychainHelper.delete(key: "lastfm_session")
        UserDefaults.standard.removeObject(forKey: "lastfm_username")
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
