import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var tracks: [Track] = [] { didSet { if !isLoading { saveLibrary() } } }
    @Published var playlists: [Playlist] = [] { didSet { if !isLoading { savePlaylists() } } }
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 1
    @Published var isShuffle = false { didSet { defaults.set(isShuffle, forKey: "shuffle") } }
    @Published var repeatMode: RepeatMode = .off { didSet { defaults.set(repeatMode.rawValue, forKey: "repeatMode") } }
    @Published var volume: Float = 1 { didSet { audioPlayer?.volume = volume; defaults.set(volume, forKey: "volume") } }
    @Published var playbackRate: Float = 1 { didSet { applyRate(); defaults.set(playbackRate, forKey: "rate") } }
    @Published var sleepTimerEnd: Date?

    @Published var crossfadeEnabled = false { didSet { defaults.set(crossfadeEnabled, forKey: "crossfade") } }
    @Published var rememberPosition = true { didSet { defaults.set(rememberPosition, forKey: "rememberPosition") } }
    @Published var hapticsEnabled = true { didSet { defaults.set(hapticsEnabled, forKey: "haptics") } }
    @Published var showLyricsCard = true { didSet { defaults.set(showLyricsCard, forKey: "showLyrics") } }
    @Published var accentChoice = "Green" { didSet { defaults.set(accentChoice, forKey: "accent") } }

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var sleepTimer: Timer?
    private let defaults = UserDefaults.standard
    private var isLoading = true

    override init() {
        super.init()
        loadSettings()
        loadLibrary()
        loadPlaylists()
        isLoading = false
        configureSession()
        configureRemoteCommands()
    }

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var libraryURL: URL { documents.appendingPathComponent("library.json") }
    private var playlistsURL: URL { documents.appendingPathComponent("playlists.json") }

    private func loadSettings() {
        isShuffle = defaults.bool(forKey: "shuffle")
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: "repeatMode") ?? "off") ?? .off
        volume = defaults.object(forKey: "volume") == nil ? 1 : defaults.float(forKey: "volume")
        playbackRate = defaults.object(forKey: "rate") == nil ? 1 : defaults.float(forKey: "rate")
        crossfadeEnabled = defaults.bool(forKey: "crossfade")
        rememberPosition = defaults.object(forKey: "rememberPosition") == nil ? true : defaults.bool(forKey: "rememberPosition")
        hapticsEnabled = defaults.object(forKey: "haptics") == nil ? true : defaults.bool(forKey: "haptics")
        showLyricsCard = defaults.object(forKey: "showLyrics") == nil ? true : defaults.bool(forKey: "showLyrics")
        accentChoice = defaults.string(forKey: "accent") ?? "Green"
    }

    private func loadLibrary() {
        if let data = try? Data(contentsOf: libraryURL), let decoded = try? JSONDecoder().decode([Track].self, from: data), !decoded.isEmpty { tracks = decoded } else { tracks = Track.demo }
    }
    private func saveLibrary() { if let data = try? JSONEncoder().encode(tracks) { try? data.write(to: libraryURL, options: .atomic) } }
    private func loadPlaylists() { if let data = try? Data(contentsOf: playlistsURL), let decoded = try? JSONDecoder().decode([Playlist].self, from: data) { playlists = decoded } }
    private func savePlaylists() { if let data = try? JSONEncoder().encode(playlists) { try? data.write(to: playlistsURL, options: .atomic) } }

    private func configureSession() {
        do { let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .default); try session.setActive(true) } catch { print("Audio session error: \(error)") }
    }

    func url(for track: Track) -> URL? {
        if let path = track.filePath { let u = documents.appendingPathComponent(path); if FileManager.default.fileExists(atPath: u.path) { return u } }
        return Bundle.main.url(forResource: track.fileName, withExtension: "mp3")
    }

    func play(_ track: Track) {
        guard let url = url(for: track) else { currentTrack = track; isPlaying = false; return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url); audioPlayer?.delegate = self; audioPlayer?.enableRate = true; audioPlayer?.volume = volume; audioPlayer?.rate = playbackRate; audioPlayer?.prepareToPlay()
            currentTrack = track; duration = audioPlayer?.duration ?? 1
            if rememberPosition { let p = defaults.double(forKey: "position_\(track.id.uuidString)"); if p > 0 && p < duration - 5 { audioPlayer?.currentTime = p } }
            audioPlayer?.play(); isPlaying = true; incrementPlayCount(track.id); startTimer(); updateNowPlaying(); haptic()
        } catch { print("Playback error: \(error)") }
    }

    func togglePlayPause() {
        guard let p = audioPlayer else { if let t = currentTrack ?? tracks.first { play(t) }; return }
        if p.isPlaying { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }; updateNowPlaying(); haptic()
    }
    func next() { guard !tracks.isEmpty else { return }; if isShuffle, let t = tracks.randomElement() { play(t); return }; guard let c = currentTrack, let i = tracks.firstIndex(where: {$0.id == c.id}) else { play(tracks[0]); return }; play(tracks[(i + 1) % tracks.count]) }
    func previous() { if progress > 4 { seek(to: 0); return }; guard !tracks.isEmpty else { return }; guard let c = currentTrack, let i = tracks.firstIndex(where: {$0.id == c.id}) else { play(tracks[0]); return }; play(tracks[(i - 1 + tracks.count) % tracks.count]) }
    func seek(to value: Double) { audioPlayer?.currentTime = value; progress = value; updateNowPlaying() }
    func skip(seconds: Double) { seek(to: min(max(progress + seconds, 0), duration)) }
    func setRepeatNext() { repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off }
    private func applyRate() { audioPlayer?.enableRate = true; audioPlayer?.rate = playbackRate }

    private func startTimer() {
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in guard let self, let p = self.audioPlayer else { return }; self.progress = p.currentTime; self.duration = max(p.duration, 1); if self.rememberPosition, let id = self.currentTrack?.id { self.defaults.set(self.progress, forKey: "position_\(id.uuidString)") } } }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { if repeatMode == .one, let c = currentTrack { play(c) } else { next() } }

    func updateTrack(_ updated: Track) { guard let i = tracks.firstIndex(where: {$0.id == updated.id}) else { return }; tracks[i] = updated; if currentTrack?.id == updated.id { currentTrack = updated; updateNowPlaying() } }
    func toggleFavorite(_ id: UUID) { guard let i = tracks.firstIndex(where: {$0.id == id}) else { return }; tracks[i].isFavorite.toggle(); if currentTrack?.id == id { currentTrack = tracks[i] }; haptic() }
    func deleteTrack(_ id: UUID) { if currentTrack?.id == id { audioPlayer?.stop(); currentTrack = nil; isPlaying = false }; if let t = tracks.first(where: {$0.id == id}), let path = t.filePath { try? FileManager.default.removeItem(at: documents.appendingPathComponent(path)) }; tracks.removeAll { $0.id == id }; for i in playlists.indices { playlists[i].trackIDs.removeAll { $0 == id } } }
    private func incrementPlayCount(_ id: UUID) { if let i = tracks.firstIndex(where: {$0.id == id}) { tracks[i].playCount += 1; currentTrack = tracks[i] } }

    func importAudio(from source: URL) throws {
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension
        let stored = "\(UUID().uuidString).\(ext)"; let dest = documents.appendingPathComponent(stored); try FileManager.default.copyItem(at: source, to: dest)
        let asset = AVURLAsset(url: dest); let base = source.deletingPathExtension().lastPathComponent
        let t = Track(title: base, artist: "Unknown Artist", fileName: base, filePath: stored)
        tracks.insert(t, at: 0)
        Task { await readMetadata(for: t.id, asset: asset) }
    }

    private func readMetadata(for id: UUID, asset: AVURLAsset) async {
        do {
            let items = try await asset.load(.commonMetadata); var updated = tracks.first(where: {$0.id == id})
            for item in items {
                guard let key = item.commonKey else { continue }; let value = try? await item.load(.stringValue)
                if key == .commonKeyTitle, let value, !value.isEmpty { updated?.title = value }
                if key == .commonKeyArtist, let value, !value.isEmpty { updated?.artist = value }
                if key == .commonKeyAlbumName, let value, !value.isEmpty { updated?.album = value }
            }
            if let updated { updateTrack(updated) }
        } catch { }
    }

    func createPlaylist(name: String) { let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty else { return }; playlists.append(Playlist(name: n)) }
    func deletePlaylist(_ id: UUID) { playlists.removeAll { $0.id == id } }
    func addTrack(_ trackID: UUID, to playlistID: UUID) { guard let i = playlists.firstIndex(where: {$0.id == playlistID}) else { return }; if !playlists[i].trackIDs.contains(trackID) { playlists[i].trackIDs.append(trackID) } }
    func removeTrack(_ trackID: UUID, from playlistID: UUID) { guard let i = playlists.firstIndex(where: {$0.id == playlistID}) else { return }; playlists[i].trackIDs.removeAll { $0 == trackID } }
    func tracks(in playlist: Playlist) -> [Track] { playlist.trackIDs.compactMap { id in tracks.first(where: {$0.id == id}) } }

    func setSleepTimer(minutes: Int?) { sleepTimer?.invalidate(); guard let minutes else { sleepTimerEnd = nil; return }; sleepTimerEnd = Date().addingTimeInterval(Double(minutes * 60)); sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in Task { @MainActor in self?.audioPlayer?.pause(); self?.isPlaying = false; self?.sleepTimerEnd = nil } } }
    func resetSettings() { isShuffle = false; repeatMode = .off; volume = 1; playbackRate = 1; crossfadeEnabled = false; rememberPosition = true; hapticsEnabled = true; showLyricsCard = true; accentChoice = "Green" }
    func resetLibrary() { audioPlayer?.stop(); currentTrack = nil; isPlaying = false; tracks = Track.demo; playlists = [] }
    private func haptic() { if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }

    private func updateNowPlaying() {
        guard let c = currentTrack else { return }; var info: [String: Any] = [MPMediaItemPropertyTitle: c.title, MPMediaItemPropertyArtist: c.artist, MPMediaItemPropertyAlbumTitle: c.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: progress, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared(); c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlayPause() }; return .success }; c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlayPause() }; return .success }; c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }; c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }; c.changePlaybackPositionCommand.addTarget { [weak self] e in if let e = e as? MPChangePlaybackPositionCommandEvent { Task { @MainActor in self?.seek(to: e.positionTime) }; return .success }; return .commandFailed }
    }
}
