import Foundation

struct Track: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var album: String = "Unknown Album"
    var genre: String = ""
    var year: Int? = nil
    var fileName: String
    var filePath: String? = nil
    var artwork: String = "music.note"
    var artworkFileName: String? = nil
    var lyrics: String = ""
    var isFavorite: Bool = false
    var playCount: Int = 0
    var dateAdded: Date = Date()

    static let demo: [Track] = [
        Track(title: "Night Drive", artist: "Local Library", fileName: "night-drive"),
        Track(title: "After Hours", artist: "Local Library", fileName: "after-hours", artwork: "headphones"),
        Track(title: "Blue Horizon", artist: "Local Library", fileName: "blue-horizon", artwork: "waveform")
    ]
}

struct Playlist: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var dateCreated: Date = Date()
}

enum RepeatMode: String, Codable, CaseIterable { case off, all, one }
enum SortMode: String, CaseIterable, Identifiable { case newest = "Recently Added", title = "Title", artist = "Artist", mostPlayed = "Most Played"; var id: String { rawValue } }
