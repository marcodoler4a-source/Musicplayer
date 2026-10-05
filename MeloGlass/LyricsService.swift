import Foundation

struct LRCLIBTrack: Decodable, Identifiable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
}

enum LyricsService {
    static func search(title: String, artist: String, album: String = "", duration: Double = 0) async throws -> [LRCLIBTrack] {
        let cleanTitle = clean(title)
        let cleanArtist = clean(artist)
        let cleanAlbum = clean(album)
        let titleNoFeature = removeFeaturing(cleanTitle)
        let artistPrimary = primaryArtist(cleanArtist)

        var searches: [[URLQueryItem]] = []
        if !cleanTitle.isEmpty && !cleanArtist.isEmpty {
            var exact = [URLQueryItem(name: "track_name", value: cleanTitle), URLQueryItem(name: "artist_name", value: cleanArtist)]
            if !cleanAlbum.isEmpty { exact.append(URLQueryItem(name: "album_name", value: cleanAlbum)) }
            searches.append(exact)
            searches.append([URLQueryItem(name: "track_name", value: cleanTitle), URLQueryItem(name: "artist_name", value: artistPrimary)])
            searches.append([URLQueryItem(name: "q", value: "\(cleanTitle) \(cleanArtist)")])
        }
        if titleNoFeature != cleanTitle && !titleNoFeature.isEmpty {
            searches.append([URLQueryItem(name: "q", value: "\(titleNoFeature) \(artistPrimary)")])
        }
        if !cleanAlbum.isEmpty {
            searches.append([URLQueryItem(name: "q", value: "\(cleanTitle) \(cleanAlbum)")])
        }
        if !cleanTitle.isEmpty { searches.append([URLQueryItem(name: "q", value: cleanTitle)]) }

        // LRCLIB asks clients to make sequential requests and avoid hammering the free service.
        var seen = Set<Int>()
        var output: [LRCLIBTrack] = []
        for items in searches {
            if let batch = try? await request(items) {
                for item in batch where item.syncedLyrics?.isEmpty == false {
                    if seen.insert(item.id).inserted { output.append(item) }
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return output.sorted { lhs, rhs in
            score(lhs, title: cleanTitle, artist: cleanArtist, album: cleanAlbum, duration: duration) > score(rhs, title: cleanTitle, artist: cleanArtist, album: cleanAlbum, duration: duration)
        }
    }

    private static func request(_ items: [URLQueryItem]) async throws -> [LRCLIBTrack] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("MeloGlass/1.6 (iOS local music player)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([LRCLIBTrack].self, from: data)
    }

    private static func score(_ item: LRCLIBTrack, title: String, artist: String, album: String, duration: Double) -> Int {
        var value = 0
        if clean(item.trackName).caseInsensitiveCompare(title) == .orderedSame { value += 100 }
        if clean(item.artistName).caseInsensitiveCompare(artist) == .orderedSame { value += 70 }
        if !album.isEmpty, clean(item.albumName ?? "").caseInsensitiveCompare(album) == .orderedSame { value += 30 }
        if duration > 0, let d = item.duration, abs(d - duration) <= 3 { value += 50 }
        return value
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeFeaturing(_ value: String) -> String {
        value.replacingOccurrences(of: "(?i)\\s+(feat\\.?|ft\\.?|featuring)\\s+.*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func primaryArtist(_ value: String) -> String {
        value.components(separatedBy: CharacterSet(charactersIn: ",;&/" )).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value
    }
}
