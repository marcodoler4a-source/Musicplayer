import Foundation

struct OnlineMusicInfo: Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let releaseDate: String
    let genre: String
    let trackNumber: String
    let releaseID: String?
    let artworkURL: URL?
    let source: String
}

private struct MBResponse: Decodable { let recordings: [MBRecording] }
private struct MBRecording: Decodable {
    let id: String; let title: String; let releases: [MBRelease]?; let genres: [MBGenre]?; let tags: [MBTag]?; let artistCredit: [MBArtistCredit]; let firstReleaseDate: String?
    enum CodingKeys: String, CodingKey { case id,title,releases,genres,tags; case artistCredit="artist-credit"; case firstReleaseDate="first-release-date" }
}
private struct MBArtistCredit: Decodable { let name:String }
private struct MBGenre: Decodable { let name:String }
private struct MBTag: Decodable { let name:String; let count:Int? }
private struct MBRelease: Decodable { let id:String; let title:String; let date:String?; let media:[MBMedium]? }
private struct MBMedium: Decodable { let tracks:[MBTrack]? }
private struct MBTrack: Decodable { let number:String?; let title:String? }
private struct CoverResponse: Decodable { let images:[CoverImage] }
private struct CoverImage: Decodable { let front:Bool?; let image:String; let thumbnails:[String:String]? }

private struct ITunesResponse: Decodable { let results:[ITunesTrack] }
private struct ITunesTrack: Decodable {
    let trackId:Int?; let trackName:String?; let artistName:String?; let collectionName:String?; let releaseDate:String?; let primaryGenreName:String?; let trackNumber:Int?; let artworkUrl100:String?
}

enum MusicInfoService {
    static func search(_ query: String) async throws -> [OnlineMusicInfo] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // Search independent public music catalogs. One provider failing does not cancel the others.
        async let mbBroad = searchMusicBrainz(cleaned, limit: 50)
        async let mbLiteral = searchMusicBrainz("recording:\"\(escapeLucene(cleaned))\"", limit: 35)
        async let appleUS = searchITunes(cleaned, country: "US", limit: 50)
        async let applePH = searchITunes(cleaned, country: "PH", limit: 50)
        async let appleJP = searchITunes(cleaned, country: "JP", limit: 30)
        async let appleGB = searchITunes(cleaned, country: "GB", limit: 30)

        let groups = await [
            (try? mbBroad) ?? [],
            (try? mbLiteral) ?? [],
            (try? appleUS) ?? [],
            (try? applePH) ?? [],
            (try? appleJP) ?? [],
            (try? appleGB) ?? []
        ]

        var seen = Set<String>()
        var output: [OnlineMusicInfo] = []
        for item in groups.flatMap({ $0 }) {
            let key = normalized(item.title) + "|" + normalized(item.artist) + "|" + normalized(item.album)
            if seen.insert(key).inserted { output.append(item) }
        }
        return output
    }

    private static func searchMusicBrainz(_ query: String, limit: Int) async throws -> [OnlineMusicInfo] {
        var c = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")!
        c.queryItems = [.init(name: "query", value: query), .init(name: "fmt", value: "json"), .init(name: "limit", value: String(limit))]
        var r = URLRequest(url: c.url!)
        r.setValue("MeloGlass/1.6 (iOS local music player)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: r)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(MBResponse.self, from: data).recordings.map { rec in
            let rel = rec.releases?.first
            let no = rel?.media?.compactMap { $0.tracks }.flatMap { $0 }.first(where: { $0.title?.caseInsensitiveCompare(rec.title) == .orderedSame })?.number ?? ""
            let genre = rec.genres?.first?.name ?? rec.tags?.sorted(by: { ($0.count ?? 0) > ($1.count ?? 0) }).first?.name ?? ""
            let coverURL = rel?.id.flatMap { URL(string: "https://coverartarchive.org/release/\($0)/front-500") }
            let artist = rec.artistCredit.map { $0.name }.joined(separator: ", ")
            let album = rel?.title ?? ""
            let releaseDate = rec.firstReleaseDate ?? rel?.date ?? ""
            let releaseID = rel?.id

            return OnlineMusicInfo(
                id: "mb-" + rec.id,
                title: rec.title,
                artist: artist,
                album: album,
                releaseDate: releaseDate,
                genre: genre,
                trackNumber: no,
                releaseID: releaseID,
                artworkURL: coverURL,
                source: "MusicBrainz + Cover Art Archive"
            )
        }
    }

    private static func searchITunes(_ query: String, country: String, limit: Int) async throws -> [OnlineMusicInfo] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: query), .init(name: "country", value: country), .init(name: "media", value: "music"), .init(name: "entity", value: "song"), .init(name: "limit", value: String(limit))]
        let (data, response) = try await URLSession.shared.data(from: c.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(ITunesResponse.self, from: data).results.map { x in
            let art = x.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")) }
            return .init(id: "itunes-\(country)-\(x.trackId ?? 0)-\(x.trackName ?? "")", title: x.trackName ?? "Unknown", artist: x.artistName ?? "Unknown Artist", album: x.collectionName ?? "", releaseDate: String((x.releaseDate ?? "").prefix(10)), genre: x.primaryGenreName ?? "", trackNumber: x.trackNumber.map(String.init) ?? "", releaseID: nil, artworkURL: art, source: "Apple catalog (\(country))")
        }
    }

    static func artwork(for item: OnlineMusicInfo) async -> Data? {
        if let u = item.artworkURL, let (d, response) = try? await URLSession.shared.data(from: u), (response as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty { return d }
        return await artwork(releaseID: item.releaseID)
    }

    static func artwork(releaseID: String?) async -> Data? {
        guard let releaseID, let url = URL(string: "https://coverartarchive.org/release/\(releaseID)") else { return nil }
        var r = URLRequest(url: url)
        r.setValue("MeloGlass/1.6 (iOS local music player)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: r), (response as? HTTPURLResponse)?.statusCode == 200, let decoded = try? JSONDecoder().decode(CoverResponse.self, from: data), let cover = decoded.images.first(where: { $0.front == true }) ?? decoded.images.first else { return nil }
        let preferred = cover.thumbnails?["1200"] ?? cover.thumbnails?["500"] ?? cover.image
        guard let u = URL(string: preferred), let (d, response) = try? await URLSession.shared.data(from: u), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return d
    }

    private static func normalized(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
    }

    private static func escapeLucene(_ s: String) -> String {
        let special = CharacterSet(charactersIn: "+-&|!(){}[]^\"~*?:\\/")
        return s.unicodeScalars.map { special.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }
}
