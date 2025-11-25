@testable import MusicPlayer
import XCTest

final class LibraryScannerTests: XCTestCase {
    func testChooseAlbumArtistUsesExplicitValue() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: "The National",
            isCompilation: false,
            trackArtists: ["Artist 1", "Artist 2"],
            folderFallback: "Folder Artist"
        )

        XCTAssertEqual(artist, "The National")
    }

    func testChooseAlbumArtistFallsBackToVariousArtistsForCompilationFlag() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: nil,
            isCompilation: true,
            trackArtists: ["Artist 1", "Artist 2"],
            folderFallback: nil
        )

        XCTAssertEqual(artist, "Various Artists")
    }

    func testChooseAlbumArtistDetectsMultipleTrackArtists() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: nil,
            isCompilation: false,
            trackArtists: ["Artist 1", "Artist 2"],
            folderFallback: "Folder Artist"
        )

        XCTAssertEqual(artist, "Various Artists")
    }

    func testChooseAlbumArtistUsesSingleTrackArtistWhenOnlyOneExists() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: nil,
            isCompilation: false,
            trackArtists: ["Artist 1", "Artist 1"],
            folderFallback: "Folder Artist"
        )

        XCTAssertEqual(artist, "Artist 1")
    }

    func testChooseAlbumArtistUsesFolderFallback() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: nil,
            isCompilation: false,
            trackArtists: [],
            folderFallback: "Folder Artist"
        )

        XCTAssertEqual(artist, "Folder Artist")
    }
}
