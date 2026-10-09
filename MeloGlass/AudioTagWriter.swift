import Foundation
import UIKit

/// Writes portable ID3v2.4 metadata directly into MP3 files.
/// Other formats keep Musix's persistent metadata + .lrc sidecar because their
/// container metadata is not safely writable in-place without transcoding.
enum AudioTagWriter {
    static func write(track: Track) {
        guard track.url.pathExtension.lowercased() == "mp3" else { return }
        guard var source = try? Data(contentsOf: track.url) else { return }

        // Strip an existing ID3v2 tag so repeated edits do not stack tags.
        if source.count >= 10,
           source[0] == 0x49, source[1] == 0x44, source[2] == 0x33 {
            let tagSize = decodeSyncSafe(source[6], source[7], source[8], source[9])
            let footer = (source[5] & 0x10) != 0 ? 10 : 0
            let total = min(source.count, 10 + tagSize + footer)
            source.removeSubrange(0..<total)
        }

        var frames = Data()
        frames.append(textFrame("TIT2", track.title))
        frames.append(textFrame("TPE1", track.artist))
        frames.append(textFrame("TALB", track.album))
        frames.append(textFrame("TCON", track.genre))
        frames.append(textFrame("TDRC", track.releaseDate))
        frames.append(textFrame("TRCK", track.trackNumber))

        if let artwork = track.artworkData, let image = UIImage(data: artwork),
           let normalized = image.jpegData(compressionQuality: 0.92) {
            frames.append(pictureFrame(normalized))
        }

        if !track.lyrics.isEmpty {
            let plain = track.lyrics.map(\.text).joined(separator: "\n")
            frames.append(unsyncedLyricsFrame(plain))
            frames.append(syncedLyricsFrame(track.lyrics))
        }

        var tag = Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00]) // ID3v2.4
        tag.append(contentsOf: syncSafe(frames.count))
        tag.append(frames)

        var output = Data()
        output.append(tag)
        output.append(source)
        let temp = track.url.deletingLastPathComponent().appendingPathComponent(".musix-\(UUID().uuidString).mp3")
        do {
            try output.write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(track.url, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private static func textFrame(_ id: String, _ value: String) -> Data {
        guard !value.isEmpty else { return Data() }
        var payload = Data([0x03]) // UTF-8
        payload.append(value.data(using: .utf8) ?? Data())
        return frame(id, payload)
    }

    private static func pictureFrame(_ jpeg: Data) -> Data {
        var payload = Data([0x03])
        payload.append("image/jpeg".data(using: .utf8)!)
        payload.append(0x00)
        payload.append(0x03) // front cover
        payload.append(0x00) // empty description
        payload.append(jpeg)
        return frame("APIC", payload)
    }

    private static func unsyncedLyricsFrame(_ lyrics: String) -> Data {
        var payload = Data([0x03])
        payload.append("eng".data(using: .ascii)!)
        payload.append(0x00) // empty description
        payload.append(lyrics.data(using: .utf8) ?? Data())
        return frame("USLT", payload)
    }

    private static func syncedLyricsFrame(_ lyrics: [LyricLine]) -> Data {
        var payload = Data([0x03])
        payload.append("eng".data(using: .ascii)!)
        payload.append(0x02) // milliseconds
        payload.append(0x01) // lyrics
        payload.append(0x00) // empty descriptor
        for line in lyrics {
            payload.append(line.text.data(using: .utf8) ?? Data())
            payload.append(0x00)
            let ms = UInt32(max(0, min(Double(UInt32.max), line.time * 1000)))
            payload.append(contentsOf: [UInt8((ms >> 24) & 0xff), UInt8((ms >> 16) & 0xff), UInt8((ms >> 8) & 0xff), UInt8(ms & 0xff)])
        }
        return frame("SYLT", payload)
    }

    private static func frame(_ id: String, _ payload: Data) -> Data {
        guard payload.count > 0 else { return Data() }
        var data = Data(id.utf8)
        data.append(contentsOf: syncSafe(payload.count))
        data.append(contentsOf: [0x00, 0x00])
        data.append(payload)
        return data
    }

    private static func syncSafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7f), UInt8((value >> 14) & 0x7f), UInt8((value >> 7) & 0x7f), UInt8(value & 0x7f)]
    }

    private static func decodeSyncSafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a & 0x7f) << 21) | (Int(b & 0x7f) << 14) | (Int(c & 0x7f) << 7) | Int(d & 0x7f)
    }
}
