import Foundation
import SwiftUI

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let duration: TimeInterval
    let trackNumber: Int
    let artist: String
}

struct Album: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let year: String
    let coverData: Data?
    let tracks: [Track]

    var coverImage: Image {
        if let data = coverData, let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "music.note.house.fill")
    }
}
