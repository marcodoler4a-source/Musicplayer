import Foundation

struct OnlineMusicInfo: Identifiable, Decodable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let releaseDate: String
    let genre: String
    let trackNumber: String
    let releaseID: String?
}

private struct MBResponse: Decodable { let recordings: [MBRecording] }
private struct MBRecording: Decodable {
    let id: String
    let title: String
    let releases: [MBRelease]?
    let genres: [MBGenre]?
    let tags: [MBTag]?
    let artistCredit: [MBArtistCredit]
    let firstReleaseDate: String?
    enum CodingKeys: String, CodingKey { case id, title, releases, genres, tags; case artistCredit = "artist-credit"; case firstReleaseDate = "first-release-date" }
}
private struct MBArtistCredit: Decodable { let name: String }
private struct MBGenre: Decodable { let name: String }
private struct MBTag: Decodable { let name: String; let count: Int? }
private struct MBRelease: Decodable { let id: String; let title: String; let date: String?; let media: [MBMedium]? }
private struct MBMedium: Decodable { let tracks: [MBTrack]? }
private struct MBTrack: Decodable { let number: String?; let title: String? }
private struct CoverResponse: Decodable { let images: [CoverImage] }
private struct CoverImage: Decodable { let front: Bool?; let image: String; let thumbnails: [String:String]? }

enum MusicInfoService {
    static func search(_ query: String) async throws -> [OnlineMusicInfo] {
        var c = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")!
        c.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "20")
        ]
        var request = URLRequest(url: c.url!)
        request.setValue("MeloGlass/1.0 (local iOS music player)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(MBResponse.self, from: data)
        return decoded.recordings.map { r in
            let release = r.releases?.first
            let trackNo = release?.media?.compactMap { $0.tracks }.flatMap { $0 }.first(where: { $0.title?.caseInsensitiveCompare(r.title) == .orderedSame })?.number ?? ""
            let genre = r.genres?.first?.name ?? r.tags?.sorted(by: { ($0.count ?? 0) > ($1.count ?? 0) }).first?.name ?? ""
            return OnlineMusicInfo(
                id: r.id,
                title: r.title,
                artist: r.artistCredit.map(\.name).joined(separator: ", "),
                album: release?.title ?? "",
                releaseDate: r.firstReleaseDate ?? release?.date ?? "",
                genre: genre,
                trackNumber: trackNo,
                releaseID: release?.id
            )
        }
    }

    static func artwork(releaseID: String?) async -> Data? {
        guard let releaseID, let url = URL(string: "https://coverartarchive.org/release/\(releaseID)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("MeloGlass/1.0 (local iOS music player)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CoverResponse.self, from: data),
              let cover = decoded.images.first(where: { $0.front == true }) ?? decoded.images.first else { return nil }
        let preferred = cover.thumbnails?["500"] ?? cover.thumbnails?["large"] ?? cover.image
        guard let imageURL = URL(string: preferred), let (imageData, _) = try? await URLSession.shared.data(from: imageURL) else { return nil }
        return imageData
    }
}
