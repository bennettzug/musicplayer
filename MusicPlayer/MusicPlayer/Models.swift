import Foundation
import SwiftUI

struct Track: Identifiable, Hashable {
    let id: UUID
    let url: URL

    let title: String
    /// Optional sort key for the title (e.g. “Wall, The” instead of “The Wall”).
    let titleSort: String?

    let duration: TimeInterval
    let trackNumber: Int

    let artist: String
    /// Optional sort key for the track artist.
    let artistSort: String?

    // MusicBrainz identifiers (optional).
    let musicBrainzTrackID: String?
    let musicBrainzReleaseTrackID: String?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        titleSort: String? = nil,
        duration: TimeInterval,
        trackNumber: Int,
        artist: String,
        artistSort: String? = nil,
        musicBrainzTrackID: String? = nil,
        musicBrainzReleaseTrackID: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.titleSort = titleSort
        self.duration = duration
        self.trackNumber = trackNumber
        self.artist = artist
        self.artistSort = artistSort
        self.musicBrainzTrackID = musicBrainzTrackID
        self.musicBrainzReleaseTrackID = musicBrainzReleaseTrackID
    }
}

struct Album: Identifiable, Hashable {
    let id: UUID

    let title: String
    /// Optional sort key for the album title.
    let titleSort: String?

    let artist: String
    /// Optional sort key for the album artist.
    let artistSort: String?

    /// Display year (prefers ORIGINALYEAR, with fallback to YEAR).
    let year: String
    /// Explicit original year if present (from ORIGINALYEAR).
    let originalYear: String?

    let coverData: Data?
    let coverImage: Image
    let tracks: [Track]

    // MusicBrainz identifiers (optional).
    let musicBrainzAlbumID: String?
    let musicBrainzAlbumArtistID: String?
    let musicBrainzArtistID: String?
    let musicBrainzReleaseGroupID: String?

    init(
        id: UUID = UUID(),
        title: String,
        titleSort: String? = nil,
        artist: String,
        artistSort: String? = nil,
        year: String,
        originalYear: String? = nil,
        coverData: Data?,
        tracks: [Track],
        musicBrainzAlbumID: String? = nil,
        musicBrainzAlbumArtistID: String? = nil,
        musicBrainzArtistID: String? = nil,
        musicBrainzReleaseGroupID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.titleSort = titleSort
        self.artist = artist
        self.artistSort = artistSort
        self.year = year
        self.originalYear = originalYear
        self.coverData = coverData
        self.coverImage = Album.makeCoverImage(from: coverData)
        self.tracks = tracks
        self.musicBrainzAlbumID = musicBrainzAlbumID
        self.musicBrainzAlbumArtistID = musicBrainzAlbumArtistID
        self.musicBrainzArtistID = musicBrainzArtistID
        self.musicBrainzReleaseGroupID = musicBrainzReleaseGroupID
    }

    private static func makeCoverImage(from data: Data?) -> Image {
        if let data, let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "music.note.house.fill")
    }

    static func == (lhs: Album, rhs: Album) -> Bool {
        // Ignore coverImage in equality to keep Hashable conformance simple.
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.titleSort == rhs.titleSort &&
        lhs.artist == rhs.artist &&
        lhs.artistSort == rhs.artistSort &&
        lhs.year == rhs.year &&
        lhs.originalYear == rhs.originalYear &&
        lhs.coverData == rhs.coverData &&
        lhs.tracks == rhs.tracks &&
        lhs.musicBrainzAlbumID == rhs.musicBrainzAlbumID &&
        lhs.musicBrainzAlbumArtistID == rhs.musicBrainzAlbumArtistID &&
        lhs.musicBrainzArtistID == rhs.musicBrainzArtistID &&
        lhs.musicBrainzReleaseGroupID == rhs.musicBrainzReleaseGroupID
    }

    func hash(into hasher: inout Hasher) {
        // Omit coverImage which is not Hashable.
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(titleSort)
        hasher.combine(artist)
        hasher.combine(artistSort)
        hasher.combine(year)
        hasher.combine(originalYear)
        hasher.combine(coverData)
        hasher.combine(tracks)
        hasher.combine(musicBrainzAlbumID)
        hasher.combine(musicBrainzAlbumArtistID)
        hasher.combine(musicBrainzArtistID)
        hasher.combine(musicBrainzReleaseGroupID)
    }
}
