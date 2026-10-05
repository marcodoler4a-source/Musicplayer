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
    static func search(_ query:String) async throws -> [OnlineMusicInfo] {
        async let mb = searchMusicBrainz(query)
        async let it = searchITunes(query)
        let combined = (try? await mb) ?? []
        let apple = (try? await it) ?? []
        var seen=Set<String>(); var output:[OnlineMusicInfo]=[]
        for item in combined + apple {
            let key=(item.title+"|"+item.artist+"|"+item.album).lowercased()
            if seen.insert(key).inserted { output.append(item) }
        }
        return output
    }

    private static func searchMusicBrainz(_ query:String) async throws -> [OnlineMusicInfo] {
        var c=URLComponents(string:"https://musicbrainz.org/ws/2/recording/")!
        c.queryItems=[.init(name:"query",value:query),.init(name:"fmt",value:"json"),.init(name:"limit",value:"25")]
        var r=URLRequest(url:c.url!); r.setValue("MeloGlass/1.3 (iOS local music player)",forHTTPHeaderField:"User-Agent")
        let (data,response)=try await URLSession.shared.data(for:r)
        guard (response as? HTTPURLResponse)?.statusCode==200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(MBResponse.self,from:data).recordings.map { rec in
            let rel=rec.releases?.first
            let no=rel?.media?.compactMap{$0.tracks}.flatMap{$0}.first(where:{$0.title?.caseInsensitiveCompare(rec.title) == .orderedSame})?.number ?? ""
            let genre=rec.genres?.first?.name ?? rec.tags?.sorted(by:{($0.count ?? 0)>($1.count ?? 0)}).first?.name ?? ""
            return .init(id:"mb-"+rec.id,title:rec.title,artist:rec.artistCredit.map(\.name).joined(separator:", "),album:rel?.title ?? "",releaseDate:rec.firstReleaseDate ?? rel?.date ?? "",genre:genre,trackNumber:no,releaseID:rel?.id,artworkURL:nil,source:"MusicBrainz")
        }
    }

    private static func searchITunes(_ query:String) async throws -> [OnlineMusicInfo] {
        var c=URLComponents(string:"https://itunes.apple.com/search")!
        c.queryItems=[.init(name:"term",value:query),.init(name:"media",value:"music"),.init(name:"entity",value:"song"),.init(name:"limit",value:"25")]
        let (data,response)=try await URLSession.shared.data(from:c.url!)
        guard (response as? HTTPURLResponse)?.statusCode==200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(ITunesResponse.self,from:data).results.map { x in
            let art=x.artworkUrl100.flatMap { URL(string:$0.replacingOccurrences(of:"100x100bb",with:"600x600bb")) }
            return .init(id:"itunes-\(x.trackId ?? Int.random(in:1...999999))",title:x.trackName ?? "Unknown",artist:x.artistName ?? "Unknown Artist",album:x.collectionName ?? "",releaseDate:String((x.releaseDate ?? "").prefix(10)),genre:x.primaryGenreName ?? "",trackNumber:x.trackNumber.map(String.init) ?? "",releaseID:nil,artworkURL:art,source:"Apple catalog")
        }
    }

    static func artwork(for item:OnlineMusicInfo) async -> Data? {
        if let u=item.artworkURL, let (d,_)=try? await URLSession.shared.data(from:u) { return d }
        return await artwork(releaseID:item.releaseID)
    }

    static func artwork(releaseID:String?) async -> Data? {
        guard let releaseID, let url=URL(string:"https://coverartarchive.org/release/\(releaseID)") else{return nil}
        var r=URLRequest(url:url); r.setValue("MeloGlass/1.3 (iOS local music player)",forHTTPHeaderField:"User-Agent")
        guard let (data,response)=try? await URLSession.shared.data(for:r),(response as? HTTPURLResponse)?.statusCode==200,let decoded=try? JSONDecoder().decode(CoverResponse.self,from:data),let cover=decoded.images.first(where:{$0.front==true}) ?? decoded.images.first else{return nil}
        let preferred=cover.thumbnails?["1200"] ?? cover.thumbnails?["500"] ?? cover.image
        guard let u=URL(string:preferred),let (d,_)=try? await URLSession.shared.data(from:u) else{return nil}; return d
    }
}
