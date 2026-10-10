import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import ImageIO

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
    @Published var playlists: [MusixPlaylist] = []
    @Published var playCounts: [UUID: Int] = [:]
    // V99 preferences and smart collections are stored without changing audio files.
    @Published var animatedArtwork = UserDefaults.standard.object(forKey: "musixAnimatedArtwork") as? Bool ?? true
    @Published var volumeNormalization = UserDefaults.standard.bool(forKey: "musixVolumeNormalization")
    @Published private(set) var listeningSeconds: Double = UserDefaults.standard.double(forKey: "musixListeningSeconds")
    @Published private(set) var skippedIDs: [UUID] = UserDefaults.standard.stringArray(forKey: "musixSkippedIDs")?.compactMap(UUID.init(uuidString:)) ?? []
    func setAnimatedArtwork(_ value: Bool) { animatedArtwork = value; UserDefaults.standard.set(value, forKey: "musixAnimatedArtwork") }
    func setVolumeNormalization(_ value: Bool) { volumeNormalization = value; UserDefaults.standard.set(value, forKey: "musixVolumeNormalization"); applyNormalizedVolume() }
    enum SmartCollection: String, CaseIterable, Identifiable {
        case favorites = "Favorites", mostPlayed = "Most Played", recentlyAdded = "Recently Added", neverPlayed = "Never Played", recentlySkipped = "Recently Skipped"
        var id: String { rawValue }
    }
    func smartTracks(_ collection: SmartCollection) -> [Track] {
        switch collection {
        case .favorites: return tracks.filter { favoriteIDs.contains($0.id) }
        case .mostPlayed: return tracks.filter { playCounts[$0.id, default: 0] > 0 }.sorted { playCounts[$0.id, default: 0] > playCounts[$1.id, default: 0] }
        case .recentlyAdded: return tracks.reversed()
        case .neverPlayed: return tracks.filter { playCounts[$0.id, default: 0] == 0 }
        case .recentlySkipped: return skippedIDs.compactMap { id in tracks.first { $0.id == id } }
        }
    }
    private func recordSkip() {
        guard let song = current, isPlaying, duration > 0, time < duration - 5 else { return }
        skippedIDs.removeAll { $0 == song.id }
        skippedIDs.insert(song.id, at: 0)
        if skippedIDs.count > 100 { skippedIDs = Array(skippedIDs.prefix(100)) }
        UserDefaults.standard.set(skippedIDs.map(\.uuidString), forKey: "musixSkippedIDs")
    }
    // Analyze a short PCM sample off the main thread and attenuate louder tracks.
    // The analysis never boosts quiet recordings, reducing clipping risk.
    private var normalizedGain: Float = 1
    private func applyNormalizedVolume() {
        engine.mainMixerNode.outputVolume = volumeNormalization ? normalizedGain : 1
    }
    private func analyzeLoudness(for track: Track) {
        normalizedGain = 1
        applyNormalizedVolume()
        guard volumeNormalization else { return }
        let id = track.id
        let url = track.url
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let file = try? AVAudioFile(forReading: url) else { return }
            let format = file.processingFormat
            guard format.commonFormat == .pcmFormatFloat32,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return }
            let channels = Int(format.channelCount)
            let maxFrames = Int(min(file.length, AVAudioFramePosition(format.sampleRate * 12)))
            var frames = 0
            var sum = 0.0
            var samples = 0
            while frames < maxFrames {
                do { try file.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, maxFrames - frames))) }
                catch { break }
                let count = Int(buffer.frameLength)
                guard count > 0, let data = buffer.floatChannelData else { break }
                for channel in 0..<channels {
                    for i in 0..<count {
                        let value = Double(data[channel][i])
                        sum += value * value
                    }
                }
                samples += count * channels
                frames += count
            }
            guard samples > 0 else { return }
            let rms = sqrt(sum / Double(samples))
            let gain = Float(min(1, max(0.35, 0.15 / max(rms, 0.0001))))
            Task { @MainActor [weak self] in
                guard let self, self.current?.id == id, self.volumeNormalization else { return }
                self.normalizedGain = gain
                self.applyNormalizedVolume()
            }
        }
    }
    @Published private(set) var playbackHistory: [UUID] = UserDefaults.standard.stringArray(forKey: "musixPlaybackHistory")?.compactMap(UUID.init(uuidString:)) ?? []
    var historyTracks: [Track] { playbackHistory.compactMap { id in tracks.first { $0.id == id } } }
    private func recordHistory(_ track: Track) {
        playbackHistory.insert(track.id, at: 0)
        if playbackHistory.count > 200 { playbackHistory = Array(playbackHistory.prefix(200)) }
        UserDefaults.standard.set(playbackHistory.map(\.uuidString), forKey: "musixPlaybackHistory")
    }
    func clearPlaybackHistory() {
        playbackHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "musixPlaybackHistory")
    }

    @Published var stopAfterCurrent = false
    @Published var queueRevision = 0
    @Published var audioLevels: [CGFloat] = Array(repeating: 0.08, count: 20)
    @Published var miniPlayerExpanded = UserDefaults.standard.bool(forKey: "musixExpandedMini")
    func setMiniExpanded(_ value: Bool) { miniPlayerExpanded = value; UserDefaults.standard.set(value, forKey: "musixExpandedMini") }
    private var extraQueue: [UUID] = []
    private var extrasURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MusixExtras.json") }
    private struct Extras: Codable { var playlists: [MusixPlaylist]; var counts: [UUID: Int]; var queuedIDs: [UUID]? }
    private func loadExtras() {
        guard let data = try? Data(contentsOf: extrasURL), let value = try? JSONDecoder().decode(Extras.self, from: data) else { return }
        playlists = value.playlists; playCounts = value.counts
        let known = Set(tracks.map(\.id))
        extraQueue = (value.queuedIDs ?? []).filter { known.contains($0) }
        queueRevision += 1
    }
    private func saveExtras() {
        let value = Extras(playlists: playlists, counts: playCounts, queuedIDs: extraQueue)
        let destination = extrasURL
        persistenceQueue.async { if let data = try? JSONEncoder().encode(value) { try? data.write(to: destination, options: .atomic) } }
    }
    func createPlaylist(_ name: String) { let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty else { return }; playlists.append(MusixPlaylist(id: UUID(), name: n, trackIDs: [])); saveExtras() }
    func deletePlaylist(_ id: UUID) { playlists.removeAll { $0.id == id }; saveExtras() }
    func addToPlaylist(_ track: Track, playlist id: UUID) { guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }; if !playlists[i].trackIDs.contains(track.id) { playlists[i].trackIDs.append(track.id); saveExtras() } }
    func removeFromPlaylist(_ track: Track, playlist id: UUID) { guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }; playlists[i].trackIDs.removeAll { $0 == track.id }; saveExtras() }
    func renamePlaylist(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = trimmed
        saveExtras()
    }
    func movePlaylistTracks(_ id: UUID, from offsets: IndexSet, to destination: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].trackIDs.move(fromOffsets: offsets, toOffset: destination)
        saveExtras()
    }
    func playlistTracks(_ playlist: MusixPlaylist) -> [Track] { playlist.trackIDs.compactMap { id in tracks.first { $0.id == id } } }
    func enqueue(_ track: Track, next: Bool) { if next { extraQueue.insert(track.id, at: 0) } else { extraQueue.append(track.id) }; queueRevision += 1; saveExtras() }
    func removeQueued(at index: Int) { guard extraQueue.indices.contains(index) else { return }; extraQueue.remove(at: index); queueRevision += 1; saveExtras() }
    func moveQueued(from: IndexSet, to: Int) { extraQueue.move(fromOffsets: from, toOffset: to); queueRevision += 1; saveExtras() }
    var upcomingTracks: [Track] { extraQueue.compactMap { id in tracks.first { $0.id == id } } }


    @Published private(set) var diagnosticsMessage = "Ready"
    @Published var batterySaver = UserDefaults.standard.bool(forKey: "musixBatterySaver")
    @Published var lowMemoryMode = UserDefaults.standard.bool(forKey: "musixLowMemoryMode")
    @Published var visualizerVisible = false
    func setBatterySaver(_ enabled: Bool) { batterySaver = enabled; UserDefaults.standard.set(enabled, forKey: "musixBatterySaver") }
    func setLowMemoryMode(_ enabled: Bool) { lowMemoryMode = enabled; UserDefaults.standard.set(enabled, forKey: "musixLowMemoryMode"); if enabled { artworkCache.removeAllObjects() } }
    private let artworkCache = NSCache<NSString, UIImage>()
    func cachedArtwork(for track: Track, maxDimension: CGFloat = 500) -> UIImage? {
        let key = "\(track.id.uuidString)-\(Int(maxDimension))" as NSString
        if let image = artworkCache.object(forKey: key) { return image }
        guard let data = track.artworkData, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        if !lowMemoryMode { artworkCache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height) }
        return image
    }
    @Published private(set) var recoverableSongID: UUID?
    private var lastRecoverySaveSecond = -1
    func persistSessionForBackground() {
        saveRecoveryPoint()
        UserDefaults.standard.set(shuffle, forKey: "musixShuffle")
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "musixRepeatMode")
        UserDefaults.standard.set(Double(speed), forKey: "musixPlaybackSpeed")
    }
    private func saveRecoveryPoint() {
        guard let current else { return }
        UserDefaults.standard.set(current.id.uuidString, forKey: "musixRecoverySong")
        UserDefaults.standard.set(time, forKey: "musixRecoveryPosition")
    }
    func restorePreviousSession() {
        guard let id = recoverableSongID, let song = tracks.first(where: { $0.id == id }) else { return }
        play(song)
        seek(UserDefaults.standard.double(forKey: "musixRecoveryPosition"))
        if isPlaying { toggle() }
        recoverableSongID = nil
    }
    private let engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var transitionNode = AVAudioPlayerNode()
    private var transitionFile: AVAudioFile?
    private var transitionTrack: Track?
    private var transitionStarted = false
    private var transitionStart: Date?
    private var transitionStartFrame: AVAudioFramePosition = 0
    private var transitionElapsed: Double = 0
    @Published var crossfadeSeconds: Double = UserDefaults.standard.double(forKey: "musixCrossfadeSeconds")
    func setCrossfade(_ seconds: Double) { crossfadeSeconds = min(12, max(0, seconds)); UserDefaults.standard.set(crossfadeSeconds, forKey: "musixCrossfadeSeconds"); cancelTransition() }
    private let crossfadeMixer = AVAudioMixerNode()
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
        applyNormalizedVolume()
        configureRemote()
        observeAudioInterruptions()
        applyEQPreset(eqPreset)
        shuffle = UserDefaults.standard.bool(forKey: "musixShuffle")
        if let savedMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "musixRepeatMode") ?? "") { repeatMode = savedMode }
        let savedSpeed = UserDefaults.standard.double(forKey: "musixPlaybackSpeed")
        if savedSpeed > 0 { speed = Float(savedSpeed); timePitch.rate = speed }
        loadLibrary()
        loadExtras()
        if let raw = UserDefaults.standard.string(forKey: "musixRecoverySong") { recoverableSongID = UUID(uuidString: raw) }
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

    private var audioObservers: [NSObjectProtocol] = []
    private var resumeAfterInterruption = false
    private func observeAudioInterruptions() {
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
                if type == .began {
                    self.resumeAfterInterruption = self.isPlaying
                    self.diagnosticsMessage = "Audio interrupted"
                    self.playerNode.pause()
                    self.transitionNode.pause()
                    self.isPlaying = false
                } else {
                    let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let mayResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
                    if self.resumeAfterInterruption && mayResume {
                        self.configureAudio()
                        if !self.engine.isRunning { try? self.engine.start() }
                        if self.engine.isRunning {
                            self.playerNode.play()
                            if self.transitionStarted { self.transitionNode.play() }
                            self.isPlaying = true
                            self.diagnosticsMessage = "Playback resumed"
                            self.publish()
                        }
                    } else {
                        self.diagnosticsMessage = "Audio interruption ended"
                    }
                    self.resumeAfterInterruption = false
                }
            }
        })
        audioObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.diagnosticsMessage = "iOS reset the audio service — reopen playback" }
        })
        audioObservers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.artworkCache.removeAllObjects(); self?.diagnosticsMessage = "Artwork cache cleared after memory warning" }
        })
    }
    private func configureEngine() {
        engine.attach(playerNode)
        engine.attach(transitionNode)
        engine.attach(crossfadeMixer)
        engine.attach(equalizer)
        engine.attach(timePitch)
        // Two players must feed separate input buses on a mixer. Connecting both
        // directly to the EQ replaces a connection and can trigger an AVAudioEngine
        // graph assertion when a track starts.
        engine.connect(playerNode, to: crossfadeMixer, fromBus: 0, toBus: 0, format: nil)
        engine.connect(transitionNode, to: crossfadeMixer, fromBus: 0, toBus: 1, format: nil)
        engine.connect(crossfadeMixer, to: equalizer, format: nil)
        engine.connect(equalizer, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        timePitch.rate = speed
        // Meter the final mix at ~10Hz instead of posting a main-actor task for
        // every audio render buffer. Never touch observable state on the render thread.
        let mixer = engine.mainMixerNode
        let meterLock = NSLock()
        var lastMeterHostTime: UInt64 = 0
        mixer.installTap(onBus: 0, bufferSize: 2048, format: mixer.outputFormat(forBus: 0)) { [weak self] buffer, when in
            meterLock.lock()
            let shouldPublish = when.hostTime > lastMeterHostTime &&
                AVAudioTime.seconds(forHostTime: when.hostTime - lastMeterHostTime) >= 0.10
            if shouldPublish { lastMeterHostTime = when.hostTime }
            meterLock.unlock()
            guard shouldPublish, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            // Frequency-sensitive spectrum: 20 logarithmically spaced Goertzel
            // filters, computed only on throttled tap callbacks (~10 Hz).
            // Unlike time-slice RMS, each bar represents a different pitch band.
            let count = Int(buffer.frameLength)
            let sampleRate = max(8000.0, buffer.format.sampleRate)
            let frequencies: [Double] = (0..<20).map { index in
                55.0 * pow(14000.0 / 55.0, Double(index) / 19.0)
            }
            var levels = [CGFloat](repeating: 0.025, count: 20)
            for (index, frequency) in frequencies.enumerated() {
                let omega = 2.0 * Double.pi * frequency / sampleRate
                let coefficient = Float(2.0 * cos(omega))
                var q1: Float = 0
                var q2: Float = 0
                for sampleIndex in 0..<count {
                    let window = Float(0.5 - 0.5 * cos(2.0 * Double.pi * Double(sampleIndex) / Double(max(1, count - 1))))
                    let q0 = samples[sampleIndex] * window + coefficient * q1 - q2
                    q2 = q1
                    q1 = q0
                }
                let power = max(0, q1 * q1 + q2 * q2 - coefficient * q1 * q2)
                let magnitude = sqrt(power) / Float(max(1, count))
                // dB-domain mapping makes normal music levels visible; linear
                // scaling previously pinned virtually every band to 0.025.
                let db = 20.0 * log10(max(Double(magnitude), 1e-8))
                let normalized = (db + 75.0) / 55.0
                levels[index] = CGFloat(min(1.0, max(0.025, normalized)))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visualizerVisible, !self.batterySaver else { return }
                self.audioLevels = levels
            }
        }
        do { try engine.start() }
        catch { userError = "Audio engine could not start: \(error.localizedDescription)"; diagnosticsMessage = "Audio engine startup failed" }
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
        cancelTransition()
        if let queue { queueIDs = queue.map(\.id) }
        if queueIDs.isEmpty { queueIDs = tracks.map(\.id) }
        current = t
        analyzeLoudness(for: t)
        time = 0
        saveRecoveryPoint()
        recordHistory(t)
        playCounts[t.id, default: 0] += 1
        saveExtras()
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
        guard remaining > 0 else { isPlaying = false; time = duration; return }
        // AVAudioFrameCount is UInt32; cap the segment length to avoid integer
        // overflow on very long files.
        let segmentFrames = AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max)))
        playerNode.scheduleSegment(file, startingFrame: frame, frameCount: segmentFrames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.completionToken == token else { return }
                self.time = self.duration
                if self.transitionStarted { return }
                self.advanceAfterCompletion()
            }
        }
        if !engine.isRunning {
            configureAudio()
            do { try engine.start() }
            catch { isPlaying = false; userError = "Audio engine could not start: \(error.localizedDescription)"; diagnosticsMessage = "Audio engine restart failed"; return }
        }
        if autoplay { playerNode.play(); isPlaying = true; diagnosticsMessage = "Playing" } else { isPlaying = false }
    }

    func toggle() {
        guard audioFile != nil else { if let t = current ?? tracks.first { play(t) }; return }
        if isPlaying { resumeAfterInterruption = false; playerNode.pause(); transitionNode.pause(); isPlaying = false }
        else { if !engine.isRunning { configureAudio(); try? engine.start() }; playerNode.play(); if transitionStarted { transitionNode.play() }; isPlaying = true }
        publish()
    }

    func seek(_ v: Double) { cancelTransition(); time = v; schedule(from: v, autoplay: isPlaying); saveRecoveryPoint(); publish() }

    func activeQueue() -> [Track] {
        let lookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let resolved = queueIDs.compactMap { lookup[$0] }
        return resolved.isEmpty ? tracks : resolved
    }

    private func advanceAfterCompletion() {
        if stopAfterCurrent { stopAfterCurrent = false; cancelTransition(); playerNode.stop(); isPlaying = false; time = duration; publish(); return }
        next()
    }

    func next() {
        recordSkip()
        cancelTransition()
        if !extraQueue.isEmpty {
            let id = extraQueue.removeFirst(); queueRevision += 1; saveExtras()
            if let track = tracks.first(where: { $0.id == id }) { play(track); return }
        }
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
        cancelTransition()
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


    func updateLyricsText(for track: Track, raw: String) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsed = LRCParser.parse(trimmed)
        if parsed.isEmpty && !trimmed.isEmpty {
            parsed = trimmed.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .enumerated()
                .map { LyricLine(time: Double($0.offset) * 5.0, text: $0.element) }
        }
        tracks[i].lyrics = parsed
        if current?.id == track.id { current = tracks[i]; publish() }
        saveLRCSidecar(for: tracks[i])
        AudioTagWriter.write(track: tracks[i])
        saveLibrary()
    }

    func setRate(_ r: Float) { speed = r; timePitch.rate = r }
    func setSleep(_ mins: Int) {
        sleepMinutes = mins; sleepTimer?.invalidate(); guard mins > 0 else { return }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(mins * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying { self.toggle() }
                self.sleepMinutes = 0
                self.sleepTimer = nil
            }
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
    var activeLyric: LyricLine? {
        guard let lines = current?.lyrics, !lines.isEmpty else { return nil }
        var low = 0, high = lines.count
        while low < high { let mid = (low + high) / 2; if lines[mid].time <= time { low = mid + 1 } else { high = mid } }
        return low > 0 ? lines[low - 1] : nil
    }

    private func tick() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: batterySaver ? 1.5 : 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let render = self.playerNode.lastRenderTime, let nodeTime = self.playerNode.playerTime(forNodeTime: render), let file = self.audioFile else { return }
                self.time = min(self.duration, Double(self.startFrame + AVAudioFramePosition(nodeTime.sampleTime)) / file.processingFormat.sampleRate)
                if self.isPlaying {
                    self.listeningSeconds += self.batterySaver ? 1.5 : 1.0
                    if Int(self.listeningSeconds) % 15 <= 1 {
                        UserDefaults.standard.set(self.listeningSeconds, forKey: "musixListeningSeconds")
                    }
                }
                let second = Int(self.time)
                if second % 5 == 0 && second != self.lastRecoverySaveSecond {
                    self.lastRecoverySaveSecond = second
                    self.saveRecoveryPoint()
                }
                self.updateTransition()
            }
        }
    }


    // A second decoder/player is connected to the same EQ chain. The incoming
    // track starts before the outgoing one ends; both nodes overlap during fade.
    // For zero crossfade, it is preloaded and starts at the end boundary.
    private func nextTransitionTrack() -> Track? {
        if stopAfterCurrent { return nil }
        if let id = extraQueue.first { return tracks.first { $0.id == id } }
        let queue = activeQueue()
        if repeatMode == .one { return current }
        if shuffle { return nil } // random choice is resolved by the normal next() path
        guard let id = current?.id, let i = queue.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < queue.count { return queue[i + 1] }
        return repeatMode == .all ? queue.first : nil
    }

    private func cancelTransition() {
        transitionNode.stop()
        transitionNode.volume = 1
        playerNode.volume = 1
        transitionFile = nil
        transitionTrack = nil
        transitionStarted = false
        transitionStart = nil
        transitionElapsed = 0
    }

    private func updateTransition() {
        guard isPlaying, duration > 0 else { return }
        let remaining = max(0, duration - time)
        let fade = min(crossfadeSeconds, duration * 0.45)
        // Decode the next file ahead of the boundary on a second player node.
        if transitionFile == nil, remaining <= max(3, fade + 1),
           let next = nextTransitionTrack(), let file = try? AVAudioFile(forReading: next.url) {
            transitionFile = file
            transitionTrack = next
            transitionNode.stop()
            transitionNode.volume = fade > 0 ? 0 : 1
            transitionNode.scheduleFile(file, at: nil)
        }
        guard transitionFile != nil else { return }
        if !transitionStarted && remaining <= (fade > 0 ? fade : 0.20) {
            transitionStarted = true
            transitionStart = Date()
            transitionStartFrame = 0
            transitionElapsed = 0
            transitionNode.play()
        }
        guard transitionStarted else { return }
        if let render = transitionNode.lastRenderTime,
           let playerTime = transitionNode.playerTime(forNodeTime: render),
           let file = transitionFile {
            transitionElapsed = Double(playerTime.sampleTime) / file.processingFormat.sampleRate
        }
        if fade > 0 {
            let progress = min(1, max(0, (fade - remaining) / fade))
            playerNode.volume = Float(cos(progress * .pi / 2))
            transitionNode.volume = Float(sin(progress * .pi / 2))
        }
        if remaining <= 0.07 { finishTransition() }
    }

    private func finishTransition() {
        guard let next = transitionTrack, let file = transitionFile else { return }
        // Swap the live nodes rather than stopping the incoming decoder and
        // restarting it on the outgoing node (which caused an audible gap).
        let oldNode = playerNode
        playerNode = transitionNode
        transitionNode = oldNode
        completionToken = UUID()
        transitionNode.stop()
        transitionNode.volume = 1
        playerNode.volume = 1
        let elapsed = transitionElapsed
        transitionFile = nil
        transitionTrack = nil
        transitionStarted = false
        transitionStart = nil
        if extraQueue.first == next.id { extraQueue.removeFirst(); queueRevision += 1; saveExtras() }
        current = next
        analyzeLoudness(for: next)
        saveRecoveryPoint()
        recordHistory(next)
        playCounts[next.id, default: 0] += 1
        saveExtras()
        audioFile = file
        duration = Double(file.length) / file.processingFormat.sampleRate
        startFrame = 0
        time = elapsed
        completionToken = UUID()
        tick()
        publish()
    }

    private func configureAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            diagnosticsMessage = "Audio session: \(error.localizedDescription)"
        }
    }
    private func configureRemote() { let c = MPRemoteCommandCenter.shared(); c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }; c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }; c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }; c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success } }
    private func publish() { guard let t = current else { return }; var n: [String: Any] = [MPMediaItemPropertyTitle: t.title, MPMediaItemPropertyArtist: t.artist, MPMediaItemPropertyAlbumTitle: t.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: time, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0]; if let im = cachedArtwork(for: t, maxDimension: 700) { n[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: im.size) { _ in im } }; MPNowPlayingInfoCenter.default().nowPlayingInfo = n }
}
import Foundation
import CryptoKit

@MainActor extension PlayerModel {
    // Backup is a folder visible under Files > On My iPhone > Musix.
    // Copy it off-device before deleting the app.
    func exportLibraryBackup() throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("MusixBackup", isDirectory: true)
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("Audio", isDirectory: true)
        try fm.createDirectory(at: audio, withIntermediateDirectories: true)
        for track in tracks {
            let destination = audio.appendingPathComponent(track.url.lastPathComponent)
            if fm.fileExists(atPath: track.url.path) && !fm.fileExists(atPath: destination.path) {
                try fm.copyItem(at: track.url, to: destination)
            }
        }
        // Save pending changes before copying persistence snapshots.
        let library = libraryFileURL
        let extras = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MusixExtras.json")
        // The library snapshot is updated asynchronously by ordinary edits; the backup
        // exports current model state directly instead of relying on that pending write.
        let saved = SavedLibrary(tracks: tracks.map { t in
            SavedTrack(id: t.id, fileName: t.url.lastPathComponent, title: t.title,
                       artist: t.artist, album: t.album, artworkData: t.artworkData,
                       releaseDate: t.releaseDate, genre: t.genre, trackNumber: t.trackNumber,
                       lyrics: t.lyrics.map { SavedLyric(time: $0.time, text: $0.text) })
        }, favoriteIDs: Array(favoriteIDs))
        try JSONEncoder().encode(saved).write(to: folder.appendingPathComponent("MusixLibrary.json"), options: .atomic)
        let snapshot = BackupExtras(playlists: playlists, counts: playCounts, queuedIDs: extraQueue)
        try JSONEncoder().encode(snapshot).write(to: folder.appendingPathComponent("MusixExtras.json"), options: .atomic)
        // Include personalized artwork and app preferences in portable backups.
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for name in ["ArtistCovers", "AlbumCovers"] {
            let source = support.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: folder.appendingPathComponent(name, isDirectory: true))
            }
        }
        let settings = UserDefaults.standard.dictionaryRepresentation().filter { key, value in
            (key.hasPrefix("musix") || key == "eqPreset" || key.hasPrefix("eqBand")) &&
            PropertyListSerialization.propertyList(value, isValidFor: .binary)
        }
        try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
            .write(to: folder.appendingPathComponent("MusixSettings.plist"), options: .atomic)
        _ = library; _ = extras
        return folder
    }

    private struct BackupExtras: Codable { let playlists: [MusixPlaylist]; let counts: [UUID: Int]; let queuedIDs: [UUID]? }

    func restoreLibraryBackup() throws {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("MusixBackup", isDirectory: true)
        let saved = try JSONDecoder().decode(SavedLibrary.self, from: Data(contentsOf: folder.appendingPathComponent("MusixLibrary.json")))
        let extras = try JSONDecoder().decode(BackupExtras.self, from: Data(contentsOf: folder.appendingPathComponent("MusixExtras.json")))
        let audio = folder.appendingPathComponent("Audio", isDirectory: true)
        for track in saved.tracks {
            let source = audio.appendingPathComponent(track.fileName)
            let destination = docs.appendingPathComponent(track.fileName)
            guard fm.fileExists(atPath: source.path) else { throw NSError(domain: "MusixBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing audio: \(track.fileName)"]) }
            if !fm.fileExists(atPath: destination.path) { try fm.copyItem(at: source, to: destination) }
        }
        // Restore metadata only after all audio files are available.
        try JSONEncoder().encode(saved).write(to: libraryFileURL, options: .atomic)
        let extrasURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MusixExtras.json")
        try JSONEncoder().encode(extras).write(to: extrasURL, options: .atomic)
        // Backwards compatible: older backups may not contain these folders or settings.
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for name in ["ArtistCovers", "AlbumCovers"] {
            let source = folder.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = support.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let target = destination.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: file, to: target)
            }
        }
        let settingsURL = folder.appendingPathComponent("MusixSettings.plist")
        if let data = try? Data(contentsOf: settingsURL),
           let settings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in settings { UserDefaults.standard.set(value, forKey: key) }
            batterySaver = UserDefaults.standard.bool(forKey: "musixBatterySaver")
            lowMemoryMode = UserDefaults.standard.bool(forKey: "musixLowMemoryMode")
            miniPlayerExpanded = UserDefaults.standard.bool(forKey: "musixExpandedMini")
            crossfadeSeconds = UserDefaults.standard.double(forKey: "musixCrossfadeSeconds")
            shuffle = UserDefaults.standard.bool(forKey: "musixShuffle")
            if let mode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "musixRepeatMode") ?? "") { repeatMode = mode }
            let restoredSpeed = UserDefaults.standard.double(forKey: "musixPlaybackSpeed")
            if restoredSpeed > 0 { setRate(Float(restoredSpeed)) }
            applyEQPreset(UserDefaults.standard.string(forKey: "eqPreset") ?? "Off")
        }
        loadLibrary()
        playlists = extras.playlists
        playCounts = extras.counts
        extraQueue = (extras.queuedIDs ?? []).filter { id in tracks.contains(where: { $0.id == id }) }
        queueRevision += 1
        saveExtras()
    }

    func duplicateGroups() -> [[Track]] {
        var groups: [String: [Track]] = [:]
        for track in tracks {
            guard let handle = try? FileHandle(forReadingFrom: track.url) else { continue }
            var hasher = SHA256()
            while true {
                let chunk = handle.readData(ofLength: 1024 * 1024)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            try? handle.close()
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            groups[digest, default: []].append(track)
        }
        return groups.values.filter { $0.count > 1 }.sorted { $0.count > $1.count }
    }
}
