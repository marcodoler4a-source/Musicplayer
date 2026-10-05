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
    static func search(title: String, artist: String) async throws -> [LRCLIBTrack] {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [URLQueryItem(name:"track_name", value:title), URLQueryItem(name:"artist_name", value:artist)]
        var r = URLRequest(url:c.url!); r.setValue("MeloGlass/1.1 (iOS music player)", forHTTPHeaderField:"User-Agent")
        let (data,response) = try await URLSession.shared.data(for:r)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([LRCLIBTrack].self, from:data).filter { ($0.syncedLyrics?.isEmpty == false) }
    }
}
