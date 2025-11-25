@testable import MusicPlayer
import XCTest

final class MusicPlayerTests: XCTestCase {
    @MainActor
    func testFilteredArtistsIncludesAlbumMatches() {
        let vm = AppViewModel()
        vm.artists = ["Magnolia Electric Co."]
        vm.library = [
            Album(
                title: "Live At Cat's Cradle, September 25th, 2007",
                artist: "Magnolia Electric Co.",
                year: "",
                coverData: nil,
                tracks: sampleTracks()
            )
        ]

        vm.searchText = "live"
        let filtered = vm.filteredArtists()

        XCTAssertEqual(filtered, ["Magnolia Electric Co."])
        XCTAssertTrue(vm.isArtistExpanded("Magnolia Electric Co."))
    }

    @MainActor
    func testArtistMatchDoesNotAutoExpand() {
        let vm = AppViewModel()
        vm.artists = ["Magnolia Electric Co."]
        vm.library = [
            Album(
                title: "Live At Cat's Cradle, September 25th, 2007",
                artist: "Magnolia Electric Co.",
                year: "",
                coverData: nil,
                tracks: sampleTracks()
            )
        ]

        vm.searchText = "magnolia"

        XCTAssertFalse(vm.isArtistExpanded("Magnolia Electric Co."))
    }

    @MainActor
    func testCollapseOverrideDuringSearch() {
        let artist = "Magnolia Electric Co."
        let vm = AppViewModel()
        vm.artists = [artist]
        vm.library = [
            Album(
                title: "Live At Cat's Cradle, September 25th, 2007",
                artist: artist,
                year: "",
                coverData: nil,
                tracks: sampleTracks()
            )
        ]

        vm.searchText = "live"
        XCTAssertTrue(vm.isArtistExpanded(artist))

        vm.setArtistExpanded(artist, false)
        XCTAssertFalse(vm.isArtistExpanded(artist))

        // Changing the search clears overrides; auto-expansion should return.
        vm.searchText = "live "
        XCTAssertTrue(vm.isArtistExpanded(artist))
    }

    @MainActor
    func testManualExpansionWithoutSearch() {
        let artist = "Magnolia Electric Co."
        let vm = AppViewModel()
        vm.artists = [artist]
        vm.library = [
            Album(
                title: "Live",
                artist: artist,
                year: "",
                coverData: nil,
                tracks: sampleTracks()
            )
        ]

        XCTAssertFalse(vm.isArtistExpanded(artist))
        vm.setArtistExpanded(artist, true)
        XCTAssertTrue(vm.isArtistExpanded(artist))
    }

    private func sampleTracks() -> [Track] {
        [
            Track(url: URL(fileURLWithPath: "/tmp/track1.mp3"), title: "Track 1", duration: 200, trackNumber: 1, artist: "Artist"),
            Track(url: URL(fileURLWithPath: "/tmp/track2.mp3"), title: "Track 2", duration: 180, trackNumber: 2, artist: "Artist")
        ]
    }
}
