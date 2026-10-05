import Foundation

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String
    var album: String
    var artworkData: Data?
    var lyrics: [LyricLine] = []
}

struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum RepeatMode: String, CaseIterable { case off, all, one }
enum LibrarySort: String, CaseIterable, Identifiable {
    case title = "Title", artist = "Artist", album = "Album", recentlyAdded = "Recently Added"
    var id: String { rawValue }
}
