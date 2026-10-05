import Foundation

struct LRCLIBTrack: Decodable, Identifiable {
    let id:Int; let trackName:String; let artistName:String; let albumName:String?; let duration:Double?; let syncedLyrics:String?; let plainLyrics:String?
}

enum LyricsService {
    static func search(title:String, artist:String) async throws -> [LRCLIBTrack] {
        let cleanTitle=clean(title); let cleanArtist=clean(artist)
        async let exact=request([.init(name:"track_name",value:cleanTitle),.init(name:"artist_name",value:cleanArtist)])
        async let broad=request([.init(name:"q",value:"\(cleanTitle) \(cleanArtist)")])
        async let titleOnly=request([.init(name:"q",value:cleanTitle)])
        let sets=[(try? await exact) ?? [],(try? await broad) ?? [],(try? await titleOnly) ?? []]
        var seen=Set<Int>(); var out:[LRCLIBTrack]=[]
        for item in sets.flatMap({$0}) where item.syncedLyrics?.isEmpty == false {
            if seen.insert(item.id).inserted { out.append(item) }
        }
        return out
    }
    private static func request(_ items:[URLQueryItem]) async throws -> [LRCLIBTrack] {
        var c=URLComponents(string:"https://lrclib.net/api/search")!; c.queryItems=items
        var r=URLRequest(url:c.url!); r.setValue("MeloGlass/1.3 (iOS music player)",forHTTPHeaderField:"User-Agent")
        let (data,response)=try await URLSession.shared.data(for:r)
        guard (response as? HTTPURLResponse)?.statusCode==200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([LRCLIBTrack].self,from:data)
    }
    private static func clean(_ s:String)->String {
        s.replacingOccurrences(of:"\\([^)]*\\)",with:"",options:.regularExpression).replacingOccurrences(of:"\\[[^]]*\\]",with:"",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
