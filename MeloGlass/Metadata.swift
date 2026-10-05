import AVFoundation
import UIKit

func loadTrack(url: URL) async -> Track {
    let asset = AVURLAsset(url: url)
    var title = url.deletingPathExtension().lastPathComponent
    var artist = "Unknown Artist"
    var album = "Local Music"
    var artworkData: Data?

    do {
        let items = try await asset.load(.commonMetadata)

        for item in items {
            guard let key = item.commonKey?.rawValue else { continue }

            switch key {
            case "title":
                if let value = try? await item.load(.stringValue) {
                    title = value
                }
            case "artist":
                if let value = try? await item.load(.stringValue) {
                    artist = value
                }
            case "albumName":
                if let value = try? await item.load(.stringValue) {
                    album = value
                }
            case "artwork":
                if let value = try? await item.load(.dataValue) {
                    artworkData = value
                }
            default:
                break
            }
        }
    } catch {
        // Keep filename/default metadata when the asset has no readable tags.
    }

    return Track(
        url: url,
        title: title,
        artist: artist,
        album: album,
        artworkData: artworkData
    )
}
