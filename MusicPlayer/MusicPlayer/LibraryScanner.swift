import Foundation
import AVFoundation

/// Scans a folder for audio files, extracts metadata, and groups them into albums.
struct LibraryScanner {

    /// Scans the given root URL for audio files and returns albums.
    func scan(url root: URL) async throws -> [Album] {
        let fm = FileManager.default
        let audioExts = Set(["mp3", "m4a", "aac", "flac", "wav", "aiff", "alac"])

        // 1. Find album folders
        let albumFolders = try findAlbumFolders(
            root: root,
            audioExts: audioExts,
            fileManager: fm
        )

        guard !albumFolders.isEmpty else {
            return []
        }

        // 2. Compute signature and attempt to reuse cache
        let signature = try computeSignature(for: albumFolders, fileManager: fm)

        if let cached = try loadCache(for: root, signature: signature) {
            return cached
        }

        // 3. Build albums from scratch
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

            let sortedFiles = audioFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }

            let (albumTitle, albumArtist, albumYear, isCompilation, fallbackArtistClosure) =
                try await extractAlbumInfo(from: sortedFiles)

            let folderArtistFallback = albumArtist ?? fallbackArtistClosure(folder)

            let tracks = try await parseTracks(
                files: sortedFiles,
                albumArtistHint: folderArtistFallback
            )

            guard !tracks.isEmpty else { continue }

            let coverData = try await loadCoverData(from: sortedFiles.first)

            let title = albumTitle ?? folder.lastPathComponent
            let artist = chooseAlbumArtist(
                explicitAlbumArtist: albumArtist,
                isCompilation: isCompilation,
                trackArtists: tracks.map(\.artist),
                folderFallback: folderArtistFallback
            )
            let year = albumYear ?? ""

            let album = Album(
                title: title,
                artist: artist,
                year: year,
                coverData: coverData,
                tracks: tracks.sorted(by: { $0.trackNumber < $1.trackNumber })
            )

            albums.append(album)
        }

        // 4. Save cache
        try saveCache(albums: albums, root: root, signature: signature)
        return albums
    }

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

    /// Parses the given audio files into `Track` models, using an optional album-artist hint.
    private func parseTracks(
        files: [URL],
        albumArtistHint: String?
    ) async throws -> [Track] {
        var result: [Track] = []

        for file in files {
            let asset = AVURLAsset(url: file)

            let (rawMetadata, common): ([AVMetadataItem], [AVMetadataItem]) = try await Task.detached(priority: .background) {
                let meta = try await asset.load(.metadata)
                let common = try await asset.load(.commonMetadata)
                return (meta, common)
            }.value
            let allMetadata = rawMetadata + common

            // Title
            let title: String = {
                if let value = firstNonEmpty(
                    firstString(from: common, key: AVMetadataKey.commonKeyTitle, keySpace: .common),
                    firstString(from: asset.metadata(forFormat: .id3Metadata), key: AVMetadataIdentifier.id3MetadataTitleDescription, keySpace: .id3),
                    firstString(from: asset.metadata(forFormat: .iTunesMetadata), key: AVMetadataIdentifier.iTunesMetadataSongName, keySpace: .iTunes)
                ) {
                    return value
                }
                return file.deletingPathExtension().lastPathComponent
            }()

            // Duration
            let durationSeconds: TimeInterval = {
                let time = asset.duration
                if time.isNumeric {
                    return time.seconds
                } else {
                    return 0
                }
            }()

            // Track number (Picard usually writes "1/10" etc.)
            let trackNumber: Int = {
                // ID3 TXXX/TRCK
                if let id3Item = AVMetadataItem.metadataItems(
                    from: asset.metadata(forFormat: .id3Metadata),
                    withKey: AVMetadataIdentifier.id3MetadataTrackNumber,
                    keySpace: .id3
                ).first,
                   let s = id3Item.stringValue {
                    let firstComponent = s.split(separator: "/").first ?? ""
                    return Int(firstComponent.trimmingCharacters(in: .whitespaces)) ?? 0
                }

                // iTunes track number
                if let itunesItem = AVMetadataItem.metadataItems(
                    from: asset.metadata(forFormat: .iTunesMetadata),
                    withKey: AVMetadataIdentifier.iTunesMetadataTrackNumber,
                    keySpace: .iTunes
                ).first {
                    if let n = itunesItem.numberValue?.intValue {
                        return n
                    }
                    if let s = itunesItem.stringValue {
                        let firstComponent = s.split(separator: "/").first ?? ""
                        return Int(firstComponent.trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }

                return 0
            }()

            // Folder name as a last-ditch fallback
            let folderName = file.deletingLastPathComponent().lastPathComponent
            let fallbackArtist = folderName

            let artist = await normalizeArtist(
                from: allMetadata,
                albumArtistHint: albumArtistHint,
                fallback: fallbackArtist
            )

            let track = Track(
                url: file,
                title: title,
                duration: durationSeconds,
                trackNumber: trackNumber,
                artist: artist
            )
            result.append(track)
        }

        return result
    }

    /// Extracts album-level metadata (title, artist, year) from the given files.
    /// `fallbackArtist` should return a best-effort artist name from the folder URL.
    private func extractAlbumInfo(
        from files: [URL]
    ) async throws -> (
        title: String?,
        artist: String?,
        year: String?,
        isCompilation: Bool,
        fallbackArtist: (URL) -> String?
    ) {
        guard let first = files.first else {
            return (nil, nil, nil, false, { url in url.lastPathComponent })
        }

        let asset = AVURLAsset(url: first)

        // Load metadata at background QoS to avoid priority inversions
        let (common, all, id3, itunes): ([AVMetadataItem], [AVMetadataItem], [AVMetadataItem], [AVMetadataItem]) =
            try await Task.detached(priority: .background) {
                let common = try await asset.load(.commonMetadata)
                let meta = try await asset.load(.metadata)
                let id3 = asset.metadata(forFormat: .id3Metadata)
                let itunes = asset.metadata(forFormat: .iTunesMetadata)
                return (common, meta + common, id3, itunes)
            }.value

        // Album title
        let albumTitle: String? = {
            firstNonEmpty(
                firstString(from: common, key: AVMetadataKey.commonKeyAlbumName, keySpace: .common),
                firstString(from: id3, key: AVMetadataIdentifier.id3MetadataAlbumTitle, keySpace: .id3),
                firstString(from: itunes, key: AVMetadataIdentifier.iTunesMetadataAlbum, keySpace: .iTunes)
            )
        }()

        // Album artist via album-artist tags only (avoid picking per-track artists).
        let albumArtist: String? = await normalizeAlbumArtist(from: all)

        // Year
        let year: String? = {
            // Common creation date (often ISO-like)
            if let dateItem = AVMetadataItem.metadataItems(
                from: common,
                withKey: AVMetadataKey.commonKeyCreationDate,
                keySpace: .common
            ).first,
               let value = dateItem.stringValue {
                let yearCandidate = String(value.prefix(4))
                if Int(yearCandidate) != nil {
                    return yearCandidate
                }
                return value
            }

            // ID3 year
            if let value = firstString(
                from: id3,
                key: AVMetadataIdentifier.id3MetadataYear,
                keySpace: .id3
            ) {
                let yearCandidate = String(value.prefix(4))
                if Int(yearCandidate) != nil {
                    return yearCandidate
                }
                return value
            }

            // iTunes release date
            if let value = firstString(
                from: itunes,
                key: AVMetadataIdentifier.iTunesMetadataReleaseDate,
                keySpace: .iTunes
            ) {
                let yearCandidate = String(value.prefix(4))
                if Int(yearCandidate) != nil {
                    return yearCandidate
                }
                return value
            }

            return nil
        }()

        // Compilation flag
        let isCompilation: Bool = {
            // The iTunes keyspace uses the raw key "cpil" for compilation
            if let value = firstString(
                from: itunes,
                key: "cpil",
                keySpace: .iTunes
            )?.lowercased() {
                return value == "1" || value == "true" || value == "yes"
            }
            return false
        }()

        // Fallback artist from folder like "Artist - Album"
        let fallbackArtist: (URL) -> String? = { folderURL in
            let name = folderURL.lastPathComponent
            if let range = name.range(of: " - ") {
                let artistPart = name[..<range.lowerBound]
                return artistPart.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return name
        }

        return (albumTitle, albumArtist, year, isCompilation, fallbackArtist)
    }

    /// Attempts to load embedded or sidecar cover artwork for an album.
    private func loadCoverData(from file: URL?) async throws -> Data? {
        guard let file else { return nil }

        let asset = AVURLAsset(url: file)

        // 1. Embedded artwork in common metadata
        if let artworkItem = AVMetadataItem.metadataItems(
            from: try await asset.load(.commonMetadata),
            withKey: AVMetadataKey.commonKeyArtwork,
            keySpace: .common
        ).first,
           let data = artworkItem.dataValue,
           !data.isEmpty {
            return data
        }

        // 2. Check ID3 & iTunes for artwork
        for format in [AVMetadataFormat.id3Metadata, AVMetadataFormat.iTunesMetadata] {
            let items = asset.metadata(forFormat: format)
            var artworkItem: AVMetadataItem?
            switch format {
            case .id3Metadata:
                artworkItem = AVMetadataItem.metadataItems(
                    from: items,
                    withKey: AVMetadataIdentifier.id3MetadataAttachedPicture,
                    keySpace: .id3
                ).first
            case .iTunesMetadata:
                artworkItem = AVMetadataItem.metadataItems(
                    from: items,
                    withKey: AVMetadataIdentifier.iTunesMetadataCoverArt,
                    keySpace: .iTunes
                ).first
            default:
                break
            }
            if let artworkItem = artworkItem,
               let data = artworkItem.dataValue,
               !data.isEmpty {
                return data
            }
        }

        // 3. Sidecar images in album folder (Picard-style names)
        let fm = FileManager.default
        let folder = file.deletingLastPathComponent()
        let candidateNames = [
            "cover.jpg", "cover.png",
            "folder.jpg", "folder.png",
            "front.jpg", "front.png",
            "Cover.jpg", "Folder.jpg"
        ]

        for name in candidateNames {
            let candidate = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path),
               let data = try? Data(contentsOf: candidate),
               !data.isEmpty {
                return data
            }
        }

        return nil
    }

    // MARK: - Cache

    /// Represents a single file’s path and modification time for cache invalidation.
    private struct SignatureItem: Codable, Hashable {
        let path: String
        let modTime: TimeInterval
    }

    /// Cached representation of an album for persistence.
    private struct CachedAlbum: Codable {
        let title: String
        let artist: String
        let year: String
        let coverData: Data?
        let tracks: [CachedTrack]
    }

    /// Cached representation of a track for persistence.
    private struct CachedTrack: Codable {
        let url: URL
        let title: String
        let duration: TimeInterval
        let trackNumber: Int
        let artist: String
    }

    /// Cache versioning for on-disk format changes.
    private enum CacheVersion {
        static let current = 3
    }

    /// Computes the URL where the cache for a given library root should live.
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

        // Basic identifier derived from root path
        let identifier = root.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        return cacheDir.appendingPathComponent("\(identifier).json", isDirectory: false)
    }

    /// Computes a signature for a collection of album folders to detect changes.
    private func computeSignature(
        for folders: [URL],
        fileManager: FileManager
    ) throws -> [SignatureItem] {
        let audioExts = Set(["mp3", "m4a", "aac", "flac", "wav", "aiff", "alac"])
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

    /// Attempts to load cached albums for the given root and signature.
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
                    duration: t.duration,
                    trackNumber: t.trackNumber,
                    artist: t.artist
                )
            }

            return Album(
                title: cachedAlbum.title,
                artist: cachedAlbum.artist,
                year: cachedAlbum.year,
                coverData: cachedAlbum.coverData,
                tracks: tracks
            )
        }

        return albums
    }

    /// Persists the given albums to disk along with their signature.
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
                    duration: track.duration,
                    trackNumber: track.trackNumber,
                    artist: track.artist
                )
            }

            return CachedAlbum(
                title: album.title,
                artist: album.artist,
                year: album.year,
                coverData: album.coverData,
                tracks: cachedTracks
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

    /// Container type for encoding/decoding the full cache payload.
    private struct CachedContainer: Codable {
        let version: Int
        let signature: [SignatureItem]
        let albums: [CachedAlbum]
    }

    /// Picks the most appropriate album artist given available data.
    func chooseAlbumArtist(
        explicitAlbumArtist: String?,
        isCompilation: Bool,
        trackArtists: [String],
        folderFallback: String?
    ) -> String {
        if let explicit = explicitAlbumArtist?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return normalizeDelimiters(explicit)
        }

        let normalizedTrackArtists = trackArtists
            .map { normalizeDelimiters($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if isCompilation {
            return "Various Artists"
        }

        let uniqueArtists = Set(normalizedTrackArtists)
        if uniqueArtists.count > 1 {
            return "Various Artists"
        }

        if let single = uniqueArtists.first {
            return single
        }

        if let folder = folderFallback?.trimmingCharacters(in: .whitespacesAndNewlines),
           !folder.isEmpty {
            return normalizeDelimiters(folder)
        }

        return "Unknown Artist"
    }
}

// MARK: - Normalization helpers

/// Returns the first non-empty string in order.
func firstNonEmpty(_ values: String?...) -> String? {
    for value in values {
        if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

/// Returns the first string value for the given key/keyspace from metadata items.
func firstString(from items: [AVMetadataItem], key: Any, keySpace: AVMetadataKeySpace) -> String? {
    let matches = AVMetadataItem.metadataItems(from: items, withKey: key, keySpace: keySpace)
    return matches.compactMap { item in
        item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.first(where: { !$0.isEmpty })
}

/// Album-artist normalization that avoids falling back to per-track artists.
private func normalizeAlbumArtist(from items: [AVMetadataItem]) async -> String? {
    // ID3 "band" (album artist)
    if let value = firstString(
        from: items,
        key: AVMetadataIdentifier.id3MetadataBand,
        keySpace: .id3
    ) {
        return normalizeDelimiters(value)
    }

    // iTunes album artist
    if let value = firstString(
        from: items,
        key: AVMetadataIdentifier.iTunesMetadataAlbumArtist,
        keySpace: .iTunes
    ) {
        return normalizeDelimiters(value)
    }

    // Explicit "Various Artists" as a common artist is still meaningful.
    if let value = firstString(
        from: items,
        key: AVMetadataKey.commonKeyArtist,
        keySpace: .common
    ),
       value.lowercased().contains("various artist") {
        return normalizeDelimiters(value)
    }

    return nil
}

/// Normalizes artist metadata from AVFoundation items, preferring album-artist fields
/// and falling back to hints or a default value.
private func normalizeArtist(
    from items: [AVMetadataItem],
    albumArtistHint: String?,
    fallback: String?
) async -> String {
    // Prefer album-level artist first

    // ID3 "band" (album artist)
    if let bandItem = AVMetadataItem.metadataItems(
        from: items,
        withKey: AVMetadataIdentifier.id3MetadataBand,
        keySpace: .id3
    ).first,
       let value = bandItem.stringValue,
       !value.isEmpty {
        return normalizeDelimiters(value)
    }

    // iTunes album artist
    if let albumArtistItem = AVMetadataItem.metadataItems(
        from: items,
        withKey: AVMetadataIdentifier.iTunesMetadataAlbumArtist,
        keySpace: .iTunes
    ).first,
       let value = albumArtistItem.stringValue,
       !value.isEmpty {
        return normalizeDelimiters(value)
    }

    // Track-level artist (common key)
    if let artistItem = AVMetadataItem.metadataItems(
        from: items,
        withKey: AVMetadataKey.commonKeyArtist,
        keySpace: .common
    ).first,
       let value = artistItem.stringValue,
       !value.isEmpty {
        return normalizeDelimiters(value)
    }

    // iTunes track artist
    if let value = firstString(
        from: items,
        key: AVMetadataIdentifier.iTunesMetadataArtist,
        keySpace: .iTunes
    ) {
        return normalizeDelimiters(value)
    }

    // ID3 lead performer (TPE1)
    if let id3Lead = AVMetadataItem.metadataItems(
        from: items,
        withKey: AVMetadataIdentifier.id3MetadataLeadPerformer,
        keySpace: .id3
    ).first,
       let value = id3Lead.stringValue,
       !value.isEmpty {
        return normalizeDelimiters(value)
    }

    if let hint = albumArtistHint, !hint.isEmpty {
        return normalizeDelimiters(hint)
    }

    if let fb = fallback, !fb.isEmpty {
        return normalizeDelimiters(fb)
    }

    return "Unknown Artist"
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

// MARK: - URL helpers

private extension URL {

    /// Returns true if this URL points to a directory.
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
