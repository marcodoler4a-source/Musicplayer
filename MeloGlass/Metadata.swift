import AVFoundation
import UIKit
func loadTrack(url: URL) async -> Track {
 let asset=AVURLAsset(url:url); var title=url.deletingPathExtension().lastPathComponent, artist="Unknown Artist", album="Local Music"; var art:Data?
 if let items=try? await asset.load(.commonMetadata) { for i in items { if let key=i.commonKey?.rawValue { if key=="title", let v=try? await i.load(.stringValue), let v { title=v }; if key=="artist", let v=try? await i.load(.stringValue), let v { artist=v }; if key=="albumName", let v=try? await i.load(.stringValue), let v { album=v }; if key=="artwork", let v=try? await i.load(.dataValue), let v { art=v } } } }
 return Track(url:url,title:title,artist:artist,album:album,artworkData:art)
}
