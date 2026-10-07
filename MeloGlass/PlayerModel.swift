import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor final class PlayerModel: NSObject, ObservableObject {
    @Published var tracks: [Track] = []
    @Published var favoriteIDs: Set<UUID> = []
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var speed: Float = 1
    @Published var sleepMinutes = 0
    @Published var floatingLyrics = false
    @Published var lyricSearchResults: [LRCLIBTrack] = []
    @Published var lyricsSearching = false
    @Published var lyricsError: String?
    @Published var eqPreset: String = UserDefaults.standard.string(forKey: "eqPreset") ?? "Off"
    @Published var userError: String?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 6)
    private let timePitch = AVAudioUnitTimePitch()
    private var audioFile: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var timer: Timer?
    private var sleepTimer: Timer?
    private var queueIDs: [UUID] = []
    private var completionToken = UUID()
    private let persistenceQueue = DispatchQueue(label: "Musix.persistence", qos: .utility)

    override init() {
        super.init()
        configureAudio()
        configureEngine()
        configureRemote()
        applyEQPreset(eqPreset)
        loadLibrary()
        Task { await recoverStoredAudioFiles() }
    }

    private struct SavedTrack: Codable {
        let id: UUID
        let fileName: String
        let title: String
        let artist: String
        let album: String
        let artworkData: Data?
        let releaseDate: String
        let genre: String
        let trackNumber: String
        let lyrics: [SavedLyric]
    }

    private struct SavedLyric: Codable {
        let time: TimeInterval
        let text: String
    }

    private struct SavedLibrary: Codable {
        let tracks: [SavedTrack]
        let favoriteIDs: [UUID]
    }

    private var libraryFileURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("MusixLibrary.json")
    }

    private func saveLibrary() {
        // Snapshot the lightweight model on the main actor, then encode/write on a
        // serial utility queue. Large libraries can contain hundreds of artwork blobs;
        // JSON encoding those on the main thread caused visible delays on taps.
        let savedTracks = tracks.map { track in
            SavedTrack(id: track.id,
                       fileName: track.url.lastPathComponent,
                       title: track.title,
                       artist: track.artist,
                       album: track.album,
                       artworkData: track.artworkData,
                       releaseDate: track.releaseDate,
                       genre: track.genre,
                       trackNumber: track.trackNumber,
                       lyrics: track.lyrics.map { SavedLyric(time: $0.time, text: $0.text) })
        }
        let library = SavedLibrary(tracks: savedTracks, favoriteIDs: Array(favoriteIDs))
        let destination = libraryFileURL
        persistenceQueue.async {
            guard let data = try? JSONEncoder().encode(library) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: libraryFileURL),
              let library = try? JSONDecoder().decode(SavedLibrary.self, from: data) else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        tracks = library.tracks.compactMap { saved in
            let url = documents.appendingPathComponent(saved.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Track(id: saved.id,
                         url: url,
                         title: saved.title,
                         artist: saved.artist,
                         album: saved.album,
                         artworkData: saved.artworkData,
                         releaseDate: saved.releaseDate,
                         genre: saved.genre,
                         trackNumber: saved.trackNumber,
                         lyrics: saved.lyrics.map { LyricLine(time: $0.time, text: $0.text) })
        }
        favoriteIDs = Set(library.favoriteIDs).intersection(Set(tracks.map(\.id)))
        queueIDs = tracks.map(\.id)
    }

    private func recoverStoredAudioFiles() async {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"]
        guard let files = try? fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) else { return }
        let known = Set(tracks.map { $0.url.lastPathComponent })
        let missing = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) && !known.contains($0.lastPathComponent) }
        guard !missing.isEmpty else { return }
        for url in missing { tracks.append(await loadTrack(url: url)) }
        queueIDs = tracks.map(\.id)
        saveLibrary()
    }

    private func configureEngine() {
        engine.attach(playerNode)
        engine.attach(equalizer)
        engine.attach(timePitch)
        engine.connect(playerNode, to: equalizer, format: nil)
        engine.connect(equalizer, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        timePitch.rate = speed
        try? engine.start()
    }

    func add(urls: [URL]) {
        let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"]
        let audioURLs = urls.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        let lrcURLs = urls.filter { $0.pathExtension.lowercased() == "lrc" }

        guard !audioURLs.isEmpty || !lrcURLs.isEmpty else {
            userError = "The selected file is not a supported audio or LRC file."
            return
        }

        // Read/copy picker URLs synchronously before the picker callback returns.
        // Files can come from On My iPhone, iCloud Drive, or another File Provider.
        var lrcByBaseName: [String: String] = [:]
        for lrcURL in lrcURLs {
            let scoped = lrcURL.startAccessingSecurityScopedResource()
            defer { if scoped { lrcURL.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: lrcURL, options: [.mappedIfSafe])
                if let raw = String(data: data, encoding: .utf8) {
                    lrcByBaseName[lrcURL.deletingPathExtension().lastPathComponent.lowercased()] = raw
                }
            } catch {
                // An LRC failure must not prevent its audio file from importing.
            }
        }

        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var copied: [(sourceName: String, baseName: String, destination: URL)] = []
        var failures: [String] = []

        for sourceURL in audioURLs {
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

            let ext = sourceURL.pathExtension.lowercased()
            let originalName = sourceURL.lastPathComponent.isEmpty ? "audio.\(ext)" : sourceURL.lastPathComponent
            let destination = documents.appendingPathComponent(UUID().uuidString + "-" + originalName)

            do {
                // First try a normal sandbox copy. This works for local Files URLs and
                // many security-scoped providers and avoids NSFileCoordinator quirks.
                do {
                    try fm.copyItem(at: sourceURL, to: destination)
                } catch {
                    // Fallback for providers that vend a coordinated/document URL.
                    var coordinationError: NSError?
                    var providerError: Error?
                    let coordinator = NSFileCoordinator(filePresenter: nil)
                    coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { readableURL in
                        do {
                            if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
                            try fm.copyItem(at: readableURL, to: destination)
                        } catch {
                            providerError = error
                        }
                    }

                    if !fm.fileExists(atPath: destination.path) {
                        // Final fallback: consume the provider file while permission is
                        // active and write our own permanent copy into Documents.
                        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                        try data.write(to: destination, options: [.atomic])
                    }
                    if !fm.fileExists(atPath: destination.path) {
                        if let providerError { throw providerError }
                        if let coordinationError { throw coordinationError }
                    }
                }

                guard fm.fileExists(atPath: destination.path) else {
                    throw NSError(domain: "MusixImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "iOS did not provide readable file data."])
                }
                let attrs = try fm.attributesOfItem(atPath: destination.path)
                if let size = attrs[.size] as? NSNumber, size.int64Value == 0 {
                    throw NSError(domain: "MusixImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "The selected file is empty."])
                }
                copied.append((originalName, sourceURL.deletingPathExtension().lastPathComponent.lowercased(), destination))
            } catch {
                try? fm.removeItem(at: destination)
                failures.append("\(originalName): \(error.localizedDescription)")
            }
        }

        // If the user selected only LRC files, attach them to songs already in the library.
        // Imported audio filenames are stored as "<UUID>-<original filename>", so compare
        // against the original filename as well as the visible track title.
        if copied.isEmpty && !lrcByBaseName.isEmpty {
            var attachedCount = 0
            for (baseName, raw) in lrcByBaseName {
                let parsed = LRCParser.parse(raw)
                guard !parsed.isEmpty else { continue }

                if let index = tracks.firstIndex(where: { track in
                    let storedBase = track.url.deletingPathExtension().lastPathComponent.lowercased()
                    let originalBase: String
                    if storedBase.count > 37, storedBase[storedBase.index(storedBase.startIndex, offsetBy: 36)] == "-" {
                        originalBase = String(storedBase.dropFirst(37))
                    } else {
                        originalBase = storedBase
                    }
                    return originalBase == baseName || track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == baseName
                }) {
                    tracks[index].lyrics = parsed
                    saveLRCSidecar(for: tracks[index])
                    AudioTagWriter.write(track: tracks[index])
                    if current?.id == tracks[index].id { current = tracks[index] }
                    attachedCount += 1
                }
            }
            if attachedCount > 0 {
                saveLibrary()
                userError = attachedCount == 1 ? "LRC imported and attached successfully." : "Attached \(attachedCount) LRC files successfully."
            } else {
                userError = "LRC imported, but no matching song was found. Make the LRC filename match the audio filename, for example Saan.mp3 + Saan.lrc."
            }
            return
        }

        guard !copied.isEmpty else {
            if !audioURLs.isEmpty {
                userError = "Import failed. " + (failures.first ?? "Musix could not read the selected file. Try saving it under On My iPhone > Downloads, then import it again.")
            }
            return
        }

        Task { @MainActor in
            var importedCount = 0
            for item in copied {
                var track = await loadTrack(url: item.destination)
                if let raw = lrcByBaseName[item.baseName] {
                    track.lyrics = LRCParser.parse(raw)
                }
                tracks.append(track)
                importedCount += 1
            }
            queueIDs = tracks.map(\.id)
            saveLibrary()

            if failures.isEmpty {
                userError = importedCount == 1 ? "Imported successfully." : "Imported \(importedCount) files successfully."
            } else {
                userError = "Imported \(importedCount) file(s), but \(failures.count) failed. \(failures[0])"
            }
        }
    }

    func isFavorite(_ t: Track) -> Bool { favoriteIDs.contains(t.id) }
    func toggleFavorite(_ t: Track) { if favoriteIDs.contains(t.id) { favoriteIDs.remove(t.id) } else { favoriteIDs.insert(t.id) }; saveLibrary() }

    func applyMusicInfo(to track: Track, info: OnlineMusicInfo, artwork: Data?) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[i].title = info.title; tracks[i].artist = info.artist; tracks[i].album = info.album
        tracks[i].releaseDate = info.releaseDate; tracks[i].genre = info.genre; tracks[i].trackNumber = info.trackNumber
        if let artwork { tracks[i].artworkData = artwork }
        if current?.id == track.id { current = tracks[i]; publish() }
        saveLRCSidecar(for: tracks[i])
        AudioTagWriter.write(track: tracks[i])
        saveLibrary()
    }

    func setArtwork(for track: Track, data: Data) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[i].artworkData = data
        if current?.id == track.id { current = tracks[i]; publish() }
        AudioTagWriter.write(track: tracks[i])
        saveLibrary()
    }

    func remove(_ t: Track) {
        // Update published state first so deletion feels immediate. Disk cleanup and
        // persistence happen off the UI thread.
        tracks.removeAll { $0.id == t.id }; favoriteIDs.remove(t.id); queueIDs.removeAll { $0 == t.id }
        if current?.id == t.id { playerNode.stop(); current = nil; isPlaying = false }
        let fileURL = t.url
        persistenceQueue.async { try? FileManager.default.removeItem(at: fileURL) }
        saveLibrary()
    }

    func play(_ t: Track, queue: [Track]? = nil) {
        if let queue { queueIDs = queue.map(\.id) }
        if queueIDs.isEmpty { queueIDs = tracks.map(\.id) }
        current = t
        do {
            // AVAudioFile exposes a decoded processing format for compressed files.
            // Do not force a client PCM format here: doing so can make valid M4A/AAC
            // containers fail to open on-device.
            let file = try AVAudioFile(forReading: t.url)
            audioFile = file
            duration = Double(file.length) / file.processingFormat.sampleRate
            startFrame = 0
            schedule(from: 0, autoplay: true)
            tick(); publish()
        } catch {
            audioFile = nil
            isPlaying = false
            userError = "Could not play \(t.url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func schedule(from seconds: Double, autoplay: Bool) {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let frame = max(0, min(file.length, AVAudioFramePosition(seconds * sampleRate)))
        startFrame = frame
        let remaining = max(0, file.length - frame)
        playerNode.stop()
        completionToken = UUID()
        let token = completionToken
        playerNode.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(remaining), at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, self.completionToken == token else { return }
                self.time = self.duration
                self.next()
            }
        }
        if !engine.isRunning { try? engine.start() }
        if autoplay { playerNode.play(); isPlaying = true } else { isPlaying = false }
    }

    func toggle() {
        guard audioFile != nil else { if let t = current ?? tracks.first { play(t) }; return }
        if playerNode.isPlaying { playerNode.pause(); isPlaying = false }
        else { if !engine.isRunning { try? engine.start() }; playerNode.play(); isPlaying = true }
        publish()
    }

    func seek(_ v: Double) { time = v; schedule(from: v, autoplay: isPlaying); publish() }

    func activeQueue() -> [Track] {
        let resolved = queueIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
        return resolved.isEmpty ? tracks : resolved
    }

    func next() {
        let queue = activeQueue(); guard !queue.isEmpty else { return }
        if repeatMode == .one, let c = current { play(c, queue: queue); return }
        if shuffle {
            let choices = queue.filter { $0.id != current?.id }
            if let t = choices.randomElement() { play(t, queue: queue); return }
        }
        guard let currentID = current?.id, let index = queue.firstIndex(where: { $0.id == currentID }) else {
            if let first = queue.first { play(first, queue: queue) }; return
        }
        if index + 1 < queue.count { play(queue[index + 1], queue: queue) }
        else if repeatMode == .all, let first = queue.first { play(first, queue: queue) }
        else { playerNode.stop(); time = duration; isPlaying = false; publish() }
    }

    func previous() {
        if time > 3 { seek(0); return }
        let queue = activeQueue(); guard !queue.isEmpty else { return }
        guard let currentID = current?.id, let index = queue.firstIndex(where: { $0.id == currentID }) else {
            if let first = queue.first { play(first, queue: queue) }; return
        }
        if index > 0 { play(queue[index - 1], queue: queue) }
        else if repeatMode == .all, let last = queue.last { play(last, queue: queue) }
        else if let first = queue.first { play(first, queue: queue) }
    }

    func updateTag(for track: Track, title: String, artist: String, album: String, genre: String, releaseDate: String, trackNumber: String, artwork: Data? = nil) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[i].title = title; tracks[i].artist = artist; tracks[i].album = album; tracks[i].genre = genre; tracks[i].releaseDate = releaseDate; tracks[i].trackNumber = trackNumber; tracks[i].artworkData = artwork
        if current?.id == track.id { current = tracks[i]; publish() }
        saveLRCSidecar(for: tracks[i])
        AudioTagWriter.write(track: tracks[i])
        saveLibrary()
    }

    func setRate(_ r: Float) { speed = r; timePitch.rate = r }
    func setSleep(_ mins: Int) {
        sleepMinutes = mins; sleepTimer?.invalidate(); guard mins > 0 else { return }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(mins * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.playerNode.pause(); self?.isPlaying = false }
        }
    }

    func setEQPreset(_ preset: String) {
        eqPreset = preset; UserDefaults.standard.set(preset, forKey: "eqPreset"); applyEQPreset(preset)
    }

    func setEQBand(_ index: Int, gain: Float) {
        guard equalizer.bands.indices.contains(index) else { return }
        equalizer.bands[index].gain = gain
        UserDefaults.standard.set(gain, forKey: "eqBand\(index)")
        eqPreset = "Custom"; UserDefaults.standard.set("Custom", forKey: "eqPreset")
    }

    func eqBandGain(_ index: Int) -> Float { equalizer.bands.indices.contains(index) ? equalizer.bands[index].gain : 0 }

    private func applyEQPreset(_ preset: String) {
        let freqs: [Float] = [60, 170, 500, 1500, 5000, 12000]
        let gains: [Float]
        switch preset {
        case "Bass Boost": gains = [8, 6, 3, 0, -1, -2]
        case "Treble Boost": gains = [-2, -1, 0, 2, 6, 8]
        case "Vocal": gains = [-2, 0, 2, 5, 4, 1]
        case "Pop": gains = [3, 2, 0, 2, 4, 3]
        case "Rock": gains = [5, 3, -1, 2, 4, 5]
        case "Acoustic": gains = [2, 1, 0, 3, 4, 3]
        case "Classical": gains = [3, 2, 0, 0, 2, 4]
        case "Custom": gains = (0..<6).map { UserDefaults.standard.object(forKey: "eqBand\($0)") as? Float ?? 0 }
        default: gains = Array(repeating: 0, count: 6)
        }
        for i in 0..<6 {
            let band = equalizer.bands[i]; band.filterType = .parametric; band.frequency = freqs[i]; band.bandwidth = 1; band.gain = gains[i]; band.bypass = false
        }
        equalizer.bypass = preset == "Off"
    }

    private func saveLRCSidecar(for track: Track) {
        guard !track.lyrics.isEmpty else { return }
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
        let body = track.lyrics.map { line -> String in
            let total = max(0, line.time)
            let minutes = Int(total) / 60
            let seconds = total - Double(minutes * 60)
            return String(format: "[%02d:%05.2f]%@", minutes, seconds, line.text)
        }.joined(separator: "\n")
        try? body.write(to: lrcURL, atomically: true, encoding: .utf8)
    }

    func attachLRC(url: URL) { guard var c = current, let s = try? String(contentsOf: url, encoding: .utf8) else { return }; c.lyrics = LRCParser.parse(s); current = c; if let i = tracks.firstIndex(where: { $0.id == c.id }) { tracks[i] = c }; saveLRCSidecar(for: c); AudioTagWriter.write(track: c); saveLibrary() }
    func searchSyncedLyrics() async { guard let c = current else { return }; lyricsSearching = true; lyricsError = nil; defer { lyricsSearching = false }; do { lyricSearchResults = try await LyricsService.search(title: c.title, artist: c.artist, album: c.album, duration: duration); if lyricSearchResults.isEmpty { lyricsError = "No timestamped lyrics found." } } catch { lyricSearchResults = []; lyricsError = "Could not search synced lyrics. Check your internet connection." } }
    func applyLyrics(_ result: LRCLIBTrack) { guard var c = current, let raw = result.syncedLyrics else { return }; let parsed = LRCParser.parse(raw); guard !parsed.isEmpty else { return }; c.lyrics = parsed; current = c; if let i = tracks.firstIndex(where: { $0.id == c.id }) { tracks[i] = c }; saveLRCSidecar(for: c); AudioTagWriter.write(track: c); saveLibrary() }
    var activeLyric: LyricLine? { current?.lyrics.last(where: { $0.time <= time }) }

    private func tick() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let render = self.playerNode.lastRenderTime, let nodeTime = self.playerNode.playerTime(forNodeTime: render), let file = self.audioFile else { return }
                self.time = min(self.duration, Double(self.startFrame + AVAudioFramePosition(nodeTime.sampleTime)) / file.processingFormat.sampleRate)
            }
        }
    }

    private func configureAudio() { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay]); try? AVAudioSession.sharedInstance().setActive(true) }
    private func configureRemote() { let c = MPRemoteCommandCenter.shared(); c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }; c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }; c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }; c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success } }
    private func publish() { guard let t = current else { return }; var n: [String: Any] = [MPMediaItemPropertyTitle: t.title, MPMediaItemPropertyArtist: t.artist, MPMediaItemPropertyAlbumTitle: t.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: time, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0]; if let d = t.artworkData, let im = UIImage(data: d) { n[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: im.size) { _ in im } }; MPNowPlayingInfoCenter.default().nowPlayingInfo = n }
}
