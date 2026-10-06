import Foundation

struct Track: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var artworkData: Data?
    var releaseDate: String = ""
    var genre: String = ""
    var trackNumber: String = ""
    var lyrics: [LyricLine] = []

    init(id: UUID = UUID(), url: URL, title: String, artist: String, album: String, artworkData: Data? = nil, releaseDate: String = "", genre: String = "", trackNumber: String = "", lyrics: [LyricLine] = []) {
        self.id = id; self.url = url; self.title = title; self.artist = artist; self.album = album
        self.artworkData = artworkData; self.releaseDate = releaseDate; self.genre = genre; self.trackNumber = trackNumber; self.lyrics = lyrics
    }
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
