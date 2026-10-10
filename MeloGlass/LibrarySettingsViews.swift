import SwiftUI
import UIKit

struct MusicInfoSearchView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    let target: Track?
    @State private var query: String
    @State private var results: [OnlineMusicInfo] = []
    @State private var searching = false
    @State private var errorText: String?
    @State private var applyingID: String?

    init(target: Track? = nil) {
        self.target = target
        let initial = [target?.title, target?.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        _query = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        TextField("Song title and artist", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        Button { Task { await search() } } label: {
                            Image(systemName: "magnifyingglass").font(.title3)
                        }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
                    }.padding(.horizontal)

                    if searching { ProgressView("Searching MusicBrainz…").padding() }
                    if let errorText { Text(errorText).foregroundStyle(.secondary).multilineTextAlignment(.center).padding() }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(results) { item in
                                MusicInfoResultCard(
                                    item: item,
                                    canApply: target != nil,
                                    isApplying: applyingID == item.id
                                ) {
                                    if let target {
                                        Task { await apply(item, to: target) }
                                    }
                                }
                                .disabled(applyingID != nil)
                            }
                        }.padding(.horizontal)
                    }
                }
            }
            .navigationTitle(target == nil ? "Search Music Info" : "Find Music Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { if target != nil && !query.isEmpty { await search() } }
        }.preferredColorScheme(.dark)
    }

    @MainActor private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true; errorText = nil
        do {
            results = try await MusicInfoService.search(q)
            if results.isEmpty { errorText = "No matching music information found." }
        } catch {
            results = []; errorText = "Could not search music information. Check your internet connection and try again."
        }
        searching = false
    }

    @MainActor private func apply(_ item: OnlineMusicInfo, to track: Track) async {
        applyingID = item.id
        let art = await MusicInfoService.artwork(for: item)
        p.applyMusicInfo(to: track, info: item, artwork: art)
        applyingID = nil
        dismiss()
    }
}

struct MusicInfoResultCard: View {
    let item: OnlineMusicInfo
    let canApply: Bool
    let isApplying: Bool
    let apply: () -> Void
    @State private var artworkData: Data?
    @State private var artworkLoaded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let artworkData, let image = UIImage(data: artworkData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.08))
                        if artworkLoaded {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
            .frame(width: 82, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.artist)
                    .foregroundStyle(.secondary)
                Text(item.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !item.album.isEmpty {
                    Label(item.album, systemImage: "square.stack")
                        .font(.caption)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if !item.releaseDate.isEmpty {
                        Text(item.releaseDate).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !item.genre.isEmpty {
                        Text(item.genre).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if canApply {
                    Button(action: apply) {
                        if isApplying {
                            ProgressView()
                        } else {
                            Label("Use Info + Cover", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .task(id: item.releaseID) {
            artworkData = await MusicInfoService.artwork(for: item)
            artworkLoaded = true
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var p: PlayerModel
    @AppStorage("accentChoice") private var accentChoice = "Blue"
    @AppStorage("musixAppearanceTheme") private var appearanceTheme = "Dynamic Artwork"
    @AppStorage("musixArtworkCorners") private var artworkCorners = 14.0
    @AppStorage("musixArtworkGlow") private var artworkGlow = true
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("showArtwork") private var showArtwork = true
    @AppStorage("showMiniPlayer") private var showMiniPlayer = true
    @AppStorage("largePlayerButtons") private var largePlayerButtons = true
    @AppStorage("glassIntensity") private var glassIntensity = 0.75
    @AppStorage("librarySort") private var librarySort = LibrarySort.title.rawValue
    @AppStorage("showLyricsOverlay") private var showLyricsOverlay = true
    @AppStorage("progressLightingEnabled") private var progressLightingEnabled = true
    @AppStorage("musixReduceMotion") private var reduceMotion = false
    @AppStorage("musixHighContrast") private var highContrast = false
    @AppStorage("musixArtworkTransitions") private var artworkTransitions = true
    @AppStorage("musixResumeOnLaunch") private var resumeOnLaunch = false
    @AppStorage("musixSwipeLeftPrevious") private var swipeLeftPrevious = true
    @State private var cacheStatus = ""
    @State private var cacheBytes: Int64 = 0
    @State private var libraryBytes: Int64 = 0
    private var documentsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private func sizeOfFiles(in folder: URL) -> Int64 {
        guard let iterator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var result: Int64 = 0
        for case let url as URL in iterator {
            if let properties = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), properties.isRegularFile == true {
                result += Int64(properties.fileSize ?? 0)
            }
        }
        return result
    }
    private func formatted(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func clearTemporaryCache() {
        let folder = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var failed = 0
        for item in items { do { try FileManager.default.removeItem(at: item) } catch { failed += 1 } }
        cacheBytes = sizeOfFiles(in: folder)
        cacheStatus = failed == 0 ? "Temporary cache cleared. Imported music was not touched." : "Some temporary files are in use and could not be cleared."
    }
    var body: some View {
        Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 29))
                            .foregroundStyle(.cyan)
                            .frame(width: 54, height: 54)
                            .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Personalize Musix").font(.headline)
                            Text("Appearance, playback, storage and accessibility")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section("Now Playing") {
                    Toggle("Smooth artwork transitions", isOn: $artworkTransitions)
                    Text("Fade between album covers when changing songs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Picker("Now Playing theme", selection: $appearanceTheme) {
                        ForEach(["Dynamic Artwork", "Midnight Blue", "Deep Purple", "Pure OLED Black"], id: \.self) { theme in Text(theme).tag(theme) }
                    }
                    Toggle("Artwork glow", isOn: $artworkGlow)
                    HStack { Text("Artwork corners"); Slider(value: $artworkCorners, in: 0...28, step: 2) }
                    Picker("Accent",selection:$accentChoice){ Text("Blue").tag("Blue"); Text("Purple").tag("Purple"); Text("Green").tag("Green"); Text("Pink").tag("Pink") }
                    Toggle("Show album artwork",isOn:$showArtwork)
                    Toggle("Compact library rows",isOn:$compactRows)
                    HStack { Text("Glass intensity"); Slider(value:$glassIntensity,in:0.2...1) }
                }
                Section("Equalizer") {
                    Picker("Sound preset", selection: Binding(
                        get: { p.eqPreset },
                        set: { p.setEQPreset($0) }
                    )) {
                        ForEach(["Off", "Bass Boost", "Treble Boost", "Vocal", "Pop", "Rock", "Acoustic", "Classical", "Custom"], id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    if p.eqPreset == "Custom" {
                        ForEach(Array(["32 Hz", "64 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"].enumerated()), id: \.offset) { index, label in
                            HStack {
                                Text(label).frame(width: 62, alignment: .leading)
                                Slider(value: Binding(
                                    get: { Double(p.eqBandGain(index)) },
                                    set: { p.setEQBand(index, gain: Float($0)) }
                                ), in: -12...12, step: 0.5)
                                Text(String(format: "%+.1f", p.eqBandGain(index)))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 42)
                            }
                        }
                    }
                    Text("EQ is applied directly to Musix playback and is saved for future sessions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Player") {
                    Toggle("Progress bar lighting animation", isOn: $progressLightingEnabled)
                    Toggle("Large playback buttons",isOn:$largePlayerButtons)
                    Toggle("Show mini player",isOn:$showMiniPlayer)
                    Text("Turn off the progress bar lighting animation to use a simple static progress bar while music is playing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Performance") {
                    Toggle("Battery Saver", isOn: Binding(get: { p.batterySaver }, set: { p.setBatterySaver($0) }))
                    Toggle("Low Memory Mode", isOn: Binding(get: { p.lowMemoryMode }, set: { p.setLowMemoryMode($0) }))
                    Text("Battery Saver reduces playback progress updates and pauses the visualizer. Low Memory Mode avoids retaining decoded artwork in the cache.")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Performance Diagnostics") {
                        Form {
                            LabeledContent("Audio engine", value: p.diagnosticsMessage)
                            LabeledContent("Songs", value: String(p.tracks.count))
                            LabeledContent("Playing", value: p.isPlaying ? "Yes" : "No")
                            LabeledContent("Crossfade", value: String(format: "%.1f s", p.crossfadeSeconds))
                            LabeledContent("Battery Saver", value: p.batterySaver ? "On" : "Off")
                            if p.recoverableSongID != nil {
                                Button("Restore previous song and position") { p.restorePreviousSession() }
                            }
                        }.navigationTitle("Diagnostics")
                    }
                }
                Section("Playback Preferences") {
                    Toggle("Resume previous session on launch", isOn: $resumeOnLaunch)
                    Text("When enabled, Musix restores the last song and position without starting playback automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Swipe left for previous song", isOn: $swipeLeftPrevious)
                    Text("Turn off to reverse the Now Playing artwork swipe directions.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text("Crossfade")
                        Spacer()
                        Text(String(format: "%.0f s", p.crossfadeSeconds)).foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { p.crossfadeSeconds }, set: { p.setCrossfade($0) }), in: 0...12, step: 1)
                    Toggle("Normalize volume", isOn: Binding(get: { p.volumeNormalization }, set: { p.setVolumeNormalization($0) }))
                }
                Section("Storage Management") {
                    LabeledContent("Imported music & library files", value: formatted(libraryBytes))
                    LabeledContent("Temporary cache", value: formatted(cacheBytes))
                    Button("Refresh Storage Sizes") { cacheBytes = sizeOfFiles(in: FileManager.default.temporaryDirectory); libraryBytes = sizeOfFiles(in: documentsURL) }
                    Button("Clear Temporary Cache", role: .destructive) { clearTemporaryCache() }
                    if !cacheStatus.isEmpty { Text(cacheStatus).font(.footnote).foregroundStyle(.secondary) }
                    Text("Only temporary files are cleared. Your imported music, playlists and saved artwork remain untouched.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Accessibility & Motion") {
                    Toggle("Reduce Motion", isOn: $reduceMotion)
                    Toggle("Increase Contrast", isOn: $highContrast)
                    Text("Reduce Motion disables the Now Playing artwork pulse and artwork transition. Increased contrast strengthens the artwork border.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Library") {
                    Picker("Sort music",selection:$librarySort){ ForEach(LibrarySort.allCases){ Text($0.rawValue).tag($0.rawValue) } }
                }
                Section("Lyrics") {
                    Toggle("Show lyrics on album artwork", isOn: $showLyricsOverlay)
                    Text("Turn this off to hide the lyrics overlay from the Now Playing album artwork. You can still add or search lyrics by pressing and holding the album cover.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
            .onAppear { cacheBytes = sizeOfFiles(in: FileManager.default.temporaryDirectory); libraryBytes = sizeOfFiles(in: documentsURL) }
    }
}
