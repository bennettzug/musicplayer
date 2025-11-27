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

    func testChooseAlbumArtistUsesMajorityWhenAboveThreshold() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: nil,
            isCompilation: false,
            trackArtists: ["A", "A", "B", "B", "A"],
            folderFallback: nil
        )

        XCTAssertEqual(artist, "A")
    }

    func testChooseAlbumArtistMarksFragmentedAsVariousArtists() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: nil,
            isCompilation: false,
            trackArtists: ["A", "B", "C", "A"],
            folderFallback: nil
        )

        XCTAssertEqual(artist, "Various Artists")
    }

    func testChooseAlbumArtistFallsBackToUnknownWhenNoData() {
        let scanner = LibraryScanner()
        let artist = scanner.chooseAlbumArtist(
            explicitAlbumArtist: nil,
            isCompilation: false,
            trackArtists: [],
            folderFallback: nil
        )

        XCTAssertEqual(artist, "Unknown Artist")
    }
}
