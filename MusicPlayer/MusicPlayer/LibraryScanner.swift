import Foundation
import taglib_c

/// Scans a folder for audio files, extracts metadata, and groups them into albums.
struct LibraryScanner {

    // MARK: - Public API

    /// Scans the given root URL for audio files and returns albums.
    /// - Parameter useCache: when true, reuses a cached scan if signature matches.
    func scan(url root: URL, useCache: Bool = true) async throws -> [Album] {
        let fm = FileManager.default
        let audioExts = Set(["mp3", "m4a", "aac", "flac", "wav", "aiff", "alac", "ogg", "opus"])

        // Configure TagLib globals (UTF-8, managed strings)
        taglib_set_strings_unicode(1)
        taglib_set_string_management_enabled(1)

        // 1. Find album folders
        let albumFolders = try findAlbumFolders(
            root: root,
            audioExts: audioExts,
            fileManager: fm
        )

        guard !albumFolders.isEmpty else {
            return []
        }

        // Attempt cache reuse
        let signature = try computeSignature(for: albumFolders, fileManager: fm)
        if useCache, let cached = try loadCache(for: root, signature: signature) {
            return cached
        }

        // Build albums from scratch using TagLib
        var albums: [Album] = []

        for folder in albumFolders.sorted(by: { $0.path < $1.path }) {
            let contents = try fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            let audioFiles = contents.filter { url in
                audioExts.contains(url.pathExtension.lowercased())
            }

            guard !audioFiles.isEmpty else { continue }

            let sortedFiles = audioFiles.sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }

            // Per-track metadata from TagLib
            var rawTracks: [RawTrack] = []
            for url in sortedFiles {
                if let track = readRawTrack(at: url) {
                    rawTracks.append(track)
                }
            }
            guard !rawTracks.isEmpty else { continue }

            // Album-level fields
            let albumTitle = rawTracks.first?.albumTitle ?? folder.lastPathComponent

            let originalYearInt = rawTracks.compactMap { $0.originalYear }.first
            let yearInt = rawTracks.compactMap { $0.year }.first
            let primaryYearInt = originalYearInt ?? yearInt

            let yearString = primaryYearInt.map(String.init) ?? ""
            let originalYearString = originalYearInt.map(String.init)

            let explicitAlbumArtist = rawTracks.compactMap { $0.albumArtistTag }.first
            let trackArtists = rawTracks.map { $0.trackArtist }
            let isCompilation = rawTracks.contains { $0.isCompilationTag }

            let folderArtistFallback = folderFallbackArtist(for: folder)

            let albumArtist = chooseAlbumArtist(
                explicitAlbumArtist: explicitAlbumArtist,
                isCompilation: isCompilation,
                trackArtists: trackArtists,
                folderFallback: folderArtistFallback
            )

            let albumTitleSort = rawTracks.compactMap { $0.albumTitleSort }.first
            let albumArtistSort = rawTracks.compactMap { $0.albumArtistSort }.first

            // Cover art from TagLib (first file with a picture)
            let coverData = readAlbumArtForAlbum(files: sortedFiles)

            // Sort tracks by disc, then track, then titleSort/title
            let sortedRaw = rawTracks.sorted {
                let d1 = $0.discNumber ?? 0
                let d2 = $1.discNumber ?? 0
                if d1 != d2 { return d1 < d2 }

                let t1 = $0.trackNumber ?? 0
                let t2 = $1.trackNumber ?? 0
                if t1 != t2 { return t1 < t2 }

                let s1 = $0.titleSort ?? $0.title
                let s2 = $1.titleSort ?? $1.title
                return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
            }

            let tracks: [Track] = sortedRaw.map { r in
                Track(
                    url: r.url,
                    title: r.title,
                    titleSort: r.titleSort,
                    duration: TimeInterval(r.lengthSeconds ?? 0),
                    trackNumber: r.trackNumber ?? 0,
                    artist: r.trackArtist,
                    artistSort: r.trackArtistSort,
                    musicBrainzTrackID: r.musicBrainzTrackID,
                    musicBrainzReleaseTrackID: r.musicBrainzReleaseTrackID
                )
            }

            let albumMusicBrainzAlbumID = rawTracks.compactMap { $0.musicBrainzAlbumID }.first
            let albumMusicBrainzAlbumArtistID = rawTracks.compactMap { $0.musicBrainzAlbumArtistID }.first
            let albumMusicBrainzArtistID = rawTracks.compactMap { $0.musicBrainzArtistID }.first
            let albumMusicBrainzReleaseGroupID = rawTracks.compactMap { $0.musicBrainzReleaseGroupID }.first

            let album = Album(
                title: albumTitle,
                titleSort: albumTitleSort,
                artist: albumArtist,
                artistSort: albumArtistSort,
                year: yearString,
                originalYear: originalYearString,
                coverData: coverData,
                tracks: tracks,
                musicBrainzAlbumID: albumMusicBrainzAlbumID,
                musicBrainzAlbumArtistID: albumMusicBrainzAlbumArtistID,
                musicBrainzArtistID: albumMusicBrainzArtistID,
                musicBrainzReleaseGroupID: albumMusicBrainzReleaseGroupID
            )

            albums.append(album)
        }

        if useCache {
            try? saveCache(albums: albums, root: root, signature: signature)
        }
        return albums
    }

    // MARK: - Internal raw track model (TagLib metadata)

    private struct RawTrack {
        let url: URL

        let title: String
        let titleSort: String?

        let trackArtist: String
        let trackArtistSort: String?

        let albumTitle: String
        let albumTitleSort: String?

        let albumArtistTag: String?
        let albumArtistSort: String?

        let year: Int?
        let originalYear: Int?

        let trackNumber: Int?
        let discNumber: Int?

        let isCompilationTag: Bool
        let lengthSeconds: Int?

        // MusicBrainz identifiers
        let musicBrainzTrackID: String?
        let musicBrainzReleaseTrackID: String?
        let musicBrainzAlbumID: String?
        let musicBrainzAlbumArtistID: String?
        let musicBrainzArtistID: String?
        let musicBrainzReleaseGroupID: String?
    }

    // MARK: - TagLib helpers

    /// Parse strings like "1" or "1/15" into (main, total).
    private func parseSlashNumber(_ s: String) -> (main: Int?, total: Int?) {
        let parts = s.split(separator: "/")
        guard !parts.isEmpty else { return (nil, nil) }

        let main = Int(parts[0].trimmingCharacters(in: .whitespaces))
        let total = parts.count > 1
            ? Int(parts[1].trimmingCharacters(in: .whitespaces))
            : nil

        return (main, total)
    }

    /// Best-effort parse of a year from a string like "1996" or "1996-01-01".
    private func parseYear(from s: String) -> Int? {
        let prefix = s.prefix(4)
        guard let year = Int(prefix), year > 0 else { return nil }
        return year
    }

    /// Read first value of a TagLib property (e.g. "ALBUMARTIST").
    private func readPropertyFirst(
        _ name: String,
        from file: UnsafeMutablePointer<TagLib_File>
    ) -> String? {
        return name.withCString { keyPtr in
            guard let valuesPtr = taglib_property_get(file, keyPtr) else {
                return nil
            }
            defer {
                taglib_property_free(valuesPtr)
            }

            guard let first = valuesPtr.pointee else {
                return nil
            }

            let value = String(cString: first)
            return value.isEmpty ? nil : value
        }
    }

    /// Read a simple string field from the basic tag interface.
    private func readTagString(
        _ getter: (UnsafePointer<TagLib_Tag>?) -> UnsafeMutablePointer<CChar>?,
        tag: UnsafeMutablePointer<TagLib_Tag>
    ) -> String? {
        guard let cStr = getter(tag) else { return nil }
        let s = String(cString: cStr)
        return s.isEmpty ? nil : s
    }

    /// Read a single track's metadata via TagLib.
    private func readRawTrack(at url: URL) -> RawTrack? {
        let path = url.path

        guard let file = path.withCString({ taglib_file_new($0) }) else {
            print("TagLib: failed to open \(path)")
            return nil
        }
        defer {
            taglib_tag_free_strings()
            taglib_file_free(file)
        }

        guard taglib_file_is_valid(file) != 0 else {
            print("TagLib: invalid file \(path)")
            return nil
        }

        guard let tag = taglib_file_tag(file) else {
            print("TagLib: no tag in \(path)")
            return nil
        }

        let audioProps = taglib_file_audioproperties(file)

        // Basic tags
        let title = readTagString(taglib_tag_title, tag: tag)
            ?? url.deletingPathExtension().lastPathComponent

        let trackArtist = readTagString(taglib_tag_artist, tag: tag)
            ?? "Unknown Artist"

        let albumTitle = readTagString(taglib_tag_album, tag: tag)
            ?? url.deletingLastPathComponent().lastPathComponent

        let yearRaw = taglib_tag_year(tag)
        let year = (yearRaw == 0) ? nil : Int(yearRaw)

        // Sort variants from properties
        let titleSort       = readPropertyFirst("TITLESORT", from: file)
        let trackArtistSort = readPropertyFirst("ARTISTSORT", from: file)
        let albumTitleSort  = readPropertyFirst("ALBUMSORT", from: file)
        let albumArtistTag  = readPropertyFirst("ALBUMARTIST", from: file)
        let albumArtistSort = readPropertyFirst("ALBUMARTISTSORT", from: file)

        // MusicBrainz identifiers
        let musicBrainzTrackID = readPropertyFirst("MUSICBRAINZ_TRACKID", from: file)
        let musicBrainzReleaseTrackID = readPropertyFirst("MUSICBRAINZ_RELEASETRACKID", from: file)
        let musicBrainzAlbumID = readPropertyFirst("MUSICBRAINZ_ALBUMID", from: file)
        let musicBrainzAlbumArtistID = readPropertyFirst("MUSICBRAINZ_ALBUMARTISTID", from: file)
        let musicBrainzArtistID = readPropertyFirst("MUSICBRAINZ_ARTISTID", from: file)
        let musicBrainzReleaseGroupID = readPropertyFirst("MUSICBRAINZ_RELEASEGROUPID", from: file)

        // Original year (prefer ORIGINALYEAR, fallback to ORIGINALDATE, then YEAR)
        let originalYearString =
            readPropertyFirst("ORIGINALYEAR", from: file) ??
            readPropertyFirst("ORIGINALDATE", from: file)
        let originalYear = originalYearString.flatMap(parseYear(from:))

        // Disc number: "1" or "1/2"
        let discProp = readPropertyFirst("DISCNUMBER", from: file)
        let (discMain, _) = discProp.map(parseSlashNumber) ?? (nil, nil)

        // Track number: prefer TRACKNUMBER property ("1/15"), fallback to taglib_tag_track
        let trackProp = readPropertyFirst("TRACKNUMBER", from: file)
        let (trackMainProp, _) = trackProp.map(parseSlashNumber) ?? (nil, nil)

        let trackFromTagLib = taglib_tag_track(tag)
        let trackNumber = trackMainProp ?? ((trackFromTagLib == 0) ? nil : Int(trackFromTagLib))

        // Compilation detection: rely on RELEASETYPE and explicit “Various Artists”.
        let releaseType = readPropertyFirst("RELEASETYPE", from: file)?.lowercased()
        let releaseIsCompilation = releaseType?.contains("compilation") ?? false
        let albumArtistLower = albumArtistTag?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let albumArtistIsVA = (albumArtistLower == "various artists")
        let isCompilationTag = releaseIsCompilation || albumArtistIsVA

        // Length
        var lengthSeconds: Int? = nil
        if let props = audioProps {
            let length = taglib_audioproperties_length(props)
            lengthSeconds = length >= 0 ? Int(length) : nil
        }

        return RawTrack(
            url: url,
            title: title,
            titleSort: titleSort,
            trackArtist: trackArtist,
            trackArtistSort: trackArtistSort,
            albumTitle: albumTitle,
            albumTitleSort: albumTitleSort,
            albumArtistTag: albumArtistTag,
            albumArtistSort: albumArtistSort,
            year: year,
            originalYear: originalYear,
            trackNumber: trackNumber,
            discNumber: discMain,
            isCompilationTag: isCompilationTag,
            lengthSeconds: lengthSeconds,
            musicBrainzTrackID: musicBrainzTrackID,
            musicBrainzReleaseTrackID: musicBrainzReleaseTrackID,
            musicBrainzAlbumID: musicBrainzAlbumID,
            musicBrainzAlbumArtistID: musicBrainzAlbumArtistID,
            musicBrainzArtistID: musicBrainzArtistID,
            musicBrainzReleaseGroupID: musicBrainzReleaseGroupID
        )
    }

    /// Extract first available album art for a set of files.
    private func readAlbumArtForAlbum(files: [URL]) -> Data? {
        for url in files {
            if let data = readAlbumArtFromPath(url.path) {
                return data
            }
        }
        return nil
    }

    /// Open a file and read album art via TagLib complex properties.
    private func readAlbumArtFromPath(_ path: String) -> Data? {
        guard let file = path.withCString({ taglib_file_new($0) }) else {
            return nil
        }
        defer {
            taglib_file_free(file)
        }

        guard taglib_file_is_valid(file) != 0 else {
            return nil
        }

        return readAlbumArt(from: file)
    }

    /// Low-level TagLib "PICTURE" reader (front cover) → Data.
    private func readAlbumArt(from file: UnsafeMutablePointer<TagLib_File>) -> Data? {
        return "PICTURE".withCString { keyPtr in
            guard let props = taglib_complex_property_get(file, keyPtr) else {
                return nil
            }
            defer {
                taglib_complex_property_free(props)
            }

            var picture = TagLib_Complex_Property_Picture_Data()
            taglib_picture_from_complex_property(props, &picture)

            guard picture.size > 0,
                  let dataPtr = picture.data else {
                return nil
            }

            return Data(bytes: dataPtr, count: Int(picture.size))
        }
    }

    // MARK: - Album folder discovery

    /// Recursively finds directories that contain audio files (album folders).
    private func findAlbumFolders(
        root: URL,
        audioExts: Set<String>,
        fileManager: FileManager
    ) throws -> [URL] {
        var albumFolders = Set<URL>()

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            if values.isRegularFile == true {
                let ext = url.pathExtension.lowercased()
                if audioExts.contains(ext) {
                    albumFolders.insert(url.deletingLastPathComponent())
                }
            }
        }

        return Array(albumFolders)
    }

    // MARK: - Cache types & helpers

    private struct SignatureItem: Codable, Hashable {
        let path: String
        let modTime: TimeInterval
    }

    private struct CachedAlbum: Codable {
        let title: String
        let titleSort: String?
        let artist: String
        let artistSort: String?
        let year: String
        let originalYear: String?
        let coverData: Data?
        let tracks: [CachedTrack]
        let musicBrainzAlbumID: String?
        let musicBrainzAlbumArtistID: String?
        let musicBrainzArtistID: String?
        let musicBrainzReleaseGroupID: String?
    }

    private struct CachedTrack: Codable {
        let url: URL
        let title: String
        let titleSort: String?
        let duration: TimeInterval
        let trackNumber: Int
        let artist: String
        let artistSort: String?
        let musicBrainzTrackID: String?
        let musicBrainzReleaseTrackID: String?
    }

    private enum CacheVersion {
        // Bump to 4 to include sort keys + MusicBrainz IDs + cover image caching.
        static let current = 4
    }

    private struct CachedContainer: Codable {
        let version: Int
        let signature: [SignatureItem]
        let albums: [CachedAlbum]
    }

    private func cacheURL(for root: URL) throws -> URL {
        let fm = FileManager.default

        let baseDir = try fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let cacheDir = baseDir.appendingPathComponent("LocalAlbumLibraryCache", isDirectory: true)
        if !fm.fileExists(atPath: cacheDir.path) {
            try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        }

        let identifier = root.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        return cacheDir.appendingPathComponent("\(identifier).json", isDirectory: false)
    }

    static func clearCache() throws {
        let fm = FileManager.default
        let baseDir = try fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cacheDir = baseDir.appendingPathComponent("LocalAlbumLibraryCache", isDirectory: true)
        if fm.fileExists(atPath: cacheDir.path) {
            try fm.removeItem(at: cacheDir)
        }
    }

    private func computeSignature(
        for folders: [URL],
        fileManager: FileManager
    ) throws -> [SignatureItem] {
        let audioExts = Set(["mp3", "m4a", "aac", "flac", "wav", "aiff", "alac", "ogg", "opus"])
        var items: [SignatureItem] = []

        for folder in folders {
            let contents = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            for url in contents {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else {
                    continue
                }

                guard audioExts.contains(url.pathExtension.lowercased()) else { continue }

                let modDate = values.contentModificationDate ?? Date.distantPast
                items.append(SignatureItem(path: url.path, modTime: modDate.timeIntervalSince1970))
            }
        }

        items.sort { $0.path < $1.path }
        return items
    }

    private func loadCache(
        for root: URL,
        signature: [SignatureItem]
    ) throws -> [Album]? {
        let url = try cacheURL(for: root)
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let container = try decoder.decode(CachedContainer.self, from: data)

        guard container.version == CacheVersion.current,
              container.signature == signature else {
            return nil
        }

        let albums: [Album] = container.albums.map { cachedAlbum in
            let tracks: [Track] = cachedAlbum.tracks.map { t in
                Track(
                    url: t.url,
                    title: t.title,
                    titleSort: t.titleSort,
                    duration: t.duration,
                    trackNumber: t.trackNumber,
                    artist: t.artist,
                    artistSort: t.artistSort,
                    musicBrainzTrackID: t.musicBrainzTrackID,
                    musicBrainzReleaseTrackID: t.musicBrainzReleaseTrackID
                )
            }

            return Album(
                title: cachedAlbum.title,
                titleSort: cachedAlbum.titleSort,
                artist: cachedAlbum.artist,
                artistSort: cachedAlbum.artistSort,
                year: cachedAlbum.year,
                originalYear: cachedAlbum.originalYear,
                coverData: cachedAlbum.coverData,
                tracks: tracks,
                musicBrainzAlbumID: cachedAlbum.musicBrainzAlbumID,
                musicBrainzAlbumArtistID: cachedAlbum.musicBrainzAlbumArtistID,
                musicBrainzArtistID: cachedAlbum.musicBrainzArtistID,
                musicBrainzReleaseGroupID: cachedAlbum.musicBrainzReleaseGroupID
            )
        }

        return albums
    }

    private func saveCache(
        albums: [Album],
        root: URL,
        signature: [SignatureItem]
    ) throws {
        let url = try cacheURL(for: root)

        let cachedAlbums: [CachedAlbum] = albums.map { album in
            let cachedTracks: [CachedTrack] = album.tracks.map { track in
                CachedTrack(
                    url: track.url,
                    title: track.title,
                    titleSort: track.titleSort,
                    duration: track.duration,
                    trackNumber: track.trackNumber,
                    artist: track.artist,
                    artistSort: track.artistSort,
                    musicBrainzTrackID: track.musicBrainzTrackID,
                    musicBrainzReleaseTrackID: track.musicBrainzReleaseTrackID
                )
            }

            return CachedAlbum(
                title: album.title,
                titleSort: album.titleSort,
                artist: album.artist,
                artistSort: album.artistSort,
                year: album.year,
                originalYear: album.originalYear,
                coverData: album.coverData,
                tracks: cachedTracks,
                musicBrainzAlbumID: album.musicBrainzAlbumID,
                musicBrainzAlbumArtistID: album.musicBrainzAlbumArtistID,
                musicBrainzArtistID: album.musicBrainzArtistID,
                musicBrainzReleaseGroupID: album.musicBrainzReleaseGroupID
            )
        }

        let container = CachedContainer(
            version: CacheVersion.current,
            signature: signature,
            albums: cachedAlbums
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        let data = try encoder.encode(container)
        try data.write(to: url, options: [.atomic])
    }

    /// Remove cached scan for a root, if it exists.
    func clearCache(for root: URL) {
        guard let url = try? cacheURL(for: root) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Album artist selection

    /// Picks the most appropriate album artist given available data.
    /// - Logic:
    ///   - If explicit album artist is present, use it.
    ///   - If TagLib marks compilation, “Various Artists”.
    ///   - Otherwise, choose the *majority* track artist if it covers ≥60% of tracks.
    ///   - If very fragmented (≥3 distinct with no majority), use “Various Artists”.
    ///   - Fallback to folder name, then “Unknown Artist”.
    func chooseAlbumArtist(
        explicitAlbumArtist: String?,
        isCompilation: Bool,
        trackArtists: [String],
        folderFallback: String?
    ) -> String {

        func normalized(_ s: String?) -> String? {
            guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return normalizeDelimiters(s).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let explicit = normalized(explicitAlbumArtist) {
            return explicit
        }

        let normalizedTracks = trackArtists.compactMap { normalized($0) }

        if normalizedTracks.isEmpty {
            if let folder = normalized(folderFallback) {
                return folder
            }
            return "Unknown Artist"
        }

        if isCompilation {
            return "Various Artists"
        }

        // Frequency-based majority detection
        var counts: [String: Int] = [:]
        for a in normalizedTracks {
            counts[a, default: 0] += 1
        }

        let sorted = counts.sorted { $0.value > $1.value }
        if let (candidate, count) = sorted.first {
            let total = normalizedTracks.count
            if count * 100 >= total * 60 { // majority threshold (60%)
                return candidate
            }
        }

        // If truly fragmented and no clear majority, treat as VA
        if counts.count >= 3 {
            return "Various Artists"
        }

        if let (candidate, _) = sorted.first {
            return candidate
        }

        if let folder = normalized(folderFallback) {
            return folder
        }
        return "Unknown Artist"
    }

    /// Derive a fallback artist from the folder name (e.g. "Artist - Album").
    private func folderFallbackArtist(for folder: URL) -> String? {
        let name = folder.lastPathComponent
        if let range = name.range(of: " - ") {
            let artistPart = name[..<range.lowerBound]
            return artistPart.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    /// Normalizes delimiters in artist strings (e.g., handling “Artist 1 / Artist 2”).
    private func normalizeDelimiters(_ value: String) -> String {
        var s = value

        let replacements: [(String, String)] = [
            (" / ", ", "),
            ("/", ", "),
            (";", ", "),
            (" ,", ", "),
            (",,", ","),
            ("  ", " ")
        ]

        for (from, to) in replacements {
            while s.contains(from) {
                s = s.replacingOccurrences(of: from, with: to)
            }
        }

        while s.contains(",,") {
            s = s.replacingOccurrences(of: ",,", with: ",")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
