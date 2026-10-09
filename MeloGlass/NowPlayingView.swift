import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var showLRCImporter = false
    @State private var showInfo = false
    @State private var showLyricSearch = false
    @State private var showMusicInfoSearch = false
    @State private var showLyrics = false
    @State private var showKaraoke = false
    @State private var showSettings = false
    @AppStorage("progressLightingEnabled") private var progressLightingEnabled = true
    @State private var showArtworkMenu = false
    @State private var showTagEditor = false
    @AppStorage("showLyricsOverlay") private var showLyricsOverlay = true

    var body: some View {
        ZStack {
            SpotifyInspiredBackground(data: p.current?.artworkData)

            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    let safeBottom = max(geometry.safeAreaInsets.bottom, 8)
                    let artworkSize = min(geometry.size.width - 28, geometry.size.height * 0.465)

                    VStack(spacing: 0) {
                        topBar
                        artwork(maxWidth: artworkSize)
                        trackDetails
                            .padding(.bottom, 8)
                        lyricsPanel
                            .padding(.bottom, 10)
                        progress
                            .padding(.bottom, 4)
                        playbackControls
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, safeBottom + 4)
                    .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
                }
            }
        }
        .preferredColorScheme(.dark)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let vertical = value.translation.height
                    let horizontal = abs(value.translation.width)
                    if vertical > 110 && vertical > horizontal * 1.25 {
                        dismiss()
                    }
                }
        )
        .sheet(isPresented: $showLRCImporter) {
            LRCFilePicker { url in
                showLRCImporter = false
                let accessed = url.startAccessingSecurityScopedResource()
                p.attachLRC(url: url)
                if accessed { url.stopAccessingSecurityScopedResource() }
            } onCancel: {
                showLRCImporter = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showInfo) { MusicInfoView().environmentObject(p) }
        .sheet(isPresented: $showLyricSearch) { SyncedLyricsSearchView().environmentObject(p) }
        .sheet(isPresented: $showMusicInfoSearch) { MusicInfoSearchView(target: p.current).environmentObject(p) }
        .sheet(isPresented: $showLyrics) { FullLyricsView().environmentObject(p) }
        .fullScreenCover(isPresented: $showKaraoke) { MusixKaraokeView().environmentObject(p) }
        .sheet(isPresented: $showSettings) { PlayerSettingsView(showLyricSearch: $showLyricSearch, showLRCImporter: $showLRCImporter).environmentObject(p) }
        .sheet(isPresented: $showTagEditor) { if let track=p.current { EditAudioTagView(track:track).environmentObject(p) } }
        .confirmationDialog("Song Options", isPresented: $showArtworkMenu, titleVisibility: .visible) {
            Button("Edit Audio Tag") { showTagEditor = true }
            Button("Search Music Info") { showMusicInfoSearch = true }
            Button("Add LRC") { showLRCImporter = true }
            Button("Search Lyrics") { showLyricSearch = true }
            Button("Karaoke Lyrics") { showKaraoke = true }
            Button("Delete", role: .destructive) { if let track=p.current { p.remove(track); dismiss() } }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("PLAYING FROM YOUR LIBRARY")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.72))
                MusixMarqueeText(text: p.current?.album.isEmpty == false ? (p.current?.album ?? "Musix") : "Musix", fontSize: 14, weight: .semibold, color: .white, centered: true)
                    .frame(height: 20)
            }
            Spacer()
            Button { showTagEditor = true } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 6)
    }

    private func artwork(maxWidth: CGFloat) -> some View {
        Artwork(data: p.current?.artworkData)
            .frame(width: max(180, maxWidth), height: max(180, maxWidth))
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 28, y: 16)
            .contentShape(Rectangle())
            .onLongPressGesture { if p.current != nil { showArtworkMenu = true } }
            .padding(.top, 6)
            .padding(.bottom, 10)
    }

    private var lyricsPanel: some View {
        Group {
            if showLyricsOverlay {
                HStack(spacing: 10) {
                    Button { showLyricSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 19, weight: .bold))
                            .frame(width: 38, height: 44)
                    }
                    .accessibilityLabel("Search synced lyrics")

                    Button { showLyrics = true } label: {
                        Text(p.activeLyric?.text.isEmpty == false ? (p.activeLyric?.text ?? "") : "Lyrics")
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 116)
                    }
                    .accessibilityLabel("Open full lyrics")

                    Button { showLRCImporter = true } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 19, weight: .bold))
                            .frame(width: 38, height: 44)
                    }
                    .accessibilityLabel("Import LRC")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10)))

            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.top, 0)
    }

    private var trackDetails: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                MusixMarqueeText(text: p.current?.title ?? "Choose a song", fontSize: 20, weight: .bold, color: .white)
                    .frame(height: 26)
                MusixMarqueeText(text: p.current?.artist ?? "Unknown Artist", fontSize: 17, weight: .regular, color: UIColor.white.withAlphaComponent(0.62))
                    .frame(height: 23)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                Button { showKaraoke = true } label: {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Open full-screen Karaoke Lyrics")
                Button {
                    if let track = p.current { p.toggleFavorite(track) }
                } label: {
                    Image(systemName: p.current.map { p.isFavorite($0) } == true ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(p.current.map { p.isFavorite($0) } == true ? Color.cyan : Color.white.opacity(0.9))
                }
                .disabled(p.current == nil)
            }
            .buttonStyle(.plain)
        }
    }

    private var progress: some View {
        VStack(spacing: 5) {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !p.isPlaying || !progressLightingEnabled)) { timeline in
                GeometryReader { geo in
                    let duration = max(1, p.duration)
                    let fraction = min(max(p.time / duration, 0), 1)
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6.0) / 6.0

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                progressLightingEnabled
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [.cyan, .blue, .purple, .pink, .orange, .yellow, .green, .cyan],
                                    startPoint: UnitPoint(x: phase - 0.35, y: 0.5),
                                    endPoint: UnitPoint(x: phase + 0.65, y: 0.5)
                                ))
                                : AnyShapeStyle(Color.white)
                            )
                            .frame(width: max(0, geo.size.width * fraction), height: 8)

                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                            .offset(x: max(0, min(geo.size.width - 18, geo.size.width * fraction - 9)))
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard p.duration > 0, geo.size.width > 0 else { return }
                                let x = min(max(value.location.x, 0), geo.size.width)
                                p.seek((x / geo.size.width) * p.duration)
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(formatTime(p.time)) of \(formatTime(p.duration))")
                    .accessibilityAdjustableAction { direction in
                        let step = max(5, p.duration * 0.02)
                        switch direction {
                        case .increment: p.seek(min(p.duration, p.time + step))
                        case .decrement: p.seek(max(0, p.time - step))
                        @unknown default: break
                        }
                    }
                }
                .frame(height: 22)
            }

            HStack {
                Text(formatTime(p.time))
                Spacer()
                Text("-" + formatTime(max(0, p.duration - p.time)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.top, 0)
    }

    private var playbackControls: some View {
        HStack {
            Button { p.shuffle.toggle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(p.shuffle ? Color.cyan : Color.white.opacity(0.82))
            }
            Spacer()
            Button { p.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            Spacer()
            Button { p.toggle() } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 68, height: 68)
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: p.isPlaying ? 0 : 2)
                }
            }
            Spacer()
            Button { p.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            Spacer()
            Button { cycleRepeat() } label: {
                Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(p.repeatMode == .off ? Color.white.opacity(0.82) : Color.cyan)
            }
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.top, 0)
        .padding(.bottom, 0)
    }


    private func cycleRepeat() {
        p.repeatMode = p.repeatMode == .off ? .all : (p.repeatMode == .all ? .one : .off)
    }

    private func formatTime(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct EditAudioTagView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var genre: String
    @State private var releaseDate: String
    @State private var trackNumber: String
    @State private var artworkData: Data?
    @State private var lyricsText: String
    @State private var showArtworkImporter = false
    @State private var showMusicInfoSearch = false
    @State private var showLyricSearch = false
    @State private var showLRCImporter = false

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album)
        _genre = State(initialValue: track.genre)
        _releaseDate = State(initialValue: track.releaseDate)
        _trackNumber = State(initialValue: track.trackNumber)
        _artworkData = State(initialValue: track.artworkData)
        _lyricsText = State(initialValue: Self.lyricsString(track.lyrics))
    }

    private static func lyricsString(_ lines: [LyricLine]) -> String {
        lines.map { line in
            let totalHundredths = Int((line.time * 100).rounded())
            let minutes = totalHundredths / 6000
            let seconds = (totalHundredths % 6000) / 100
            let hundredths = totalHundredths % 100
            return String(format: "[%02d:%02d.%02d]", minutes, seconds, hundredths) + line.text
        }.joined(separator: "\n")
    }

    private func reloadFromCurrentTrack() {
        guard let latest = p.tracks.first(where: { $0.id == track.id }) else { return }
        title = latest.title
        artist = latest.artist
        album = latest.album
        genre = latest.genre
        releaseDate = latest.releaseDate
        trackNumber = latest.trackNumber
        artworkData = latest.artworkData
        lyricsText = Self.lyricsString(latest.lyrics)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Album Cover") {
                    HStack(spacing: 16) {
                        Group {
                            if let artworkData, let image = UIImage(data: artworkData) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 82, height: 82)
                        .background(.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Button("Choose from Files") { showArtworkImporter = true }
                            if artworkData != nil {
                                Button("Remove Album Cover", role: .destructive) { artworkData = nil }
                            }
                        }
                    }
                }

                Section("Audio Tag") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Album", text: $album)
                    TextField("Genre", text: $genre)
                    TextField("Release Date", text: $releaseDate)
                    TextField("Track Number", text: $trackNumber)
                }

                Section("Find Online") {
                    Button { showMusicInfoSearch = true } label: {
                        Label("Search Music Info", systemImage: "magnifyingglass")
                    }
                    Button { showLyricSearch = true } label: {
                        Label("Search Lyrics", systemImage: "text.magnifyingglass")
                    }
                    Button { showLRCImporter = true } label: {
                        Label("Add LRC File", systemImage: "doc.text")
                    }
                }

                Section("Lyrics") {
                    TextEditor(text: $lyricsText)
                        .frame(minHeight: 180)
                    Text("You can type or paste lyrics here. Timestamped LRC lines such as [00:12.50]Lyrics are supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Audio Tag")
            .fileImporter(isPresented: $showArtworkImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), UIImage(data: data) != nil { artworkData = data }
            }
            .sheet(isPresented: $showMusicInfoSearch, onDismiss: reloadFromCurrentTrack) {
                MusicInfoSearchView(target: p.tracks.first(where: { $0.id == track.id }) ?? track).environmentObject(p)
            }
            .sheet(isPresented: $showLyricSearch, onDismiss: reloadFromCurrentTrack) {
                SyncedLyricsSearchView().environmentObject(p)
            }
            .sheet(isPresented: $showLRCImporter, onDismiss: reloadFromCurrentTrack) {
                LRCFilePicker { url in
                    showLRCImporter = false
                    let accessed = url.startAccessingSecurityScopedResource()
                    p.attachLRC(url: url)
                    if accessed { url.stopAccessingSecurityScopedResource() }
                } onCancel: {
                    showLRCImporter = false
                }
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        p.updateTag(for: track, title: title, artist: artist, album: album, genre: genre, releaseDate: releaseDate, trackNumber: trackNumber, artwork: artworkData)
                        p.updateLyricsText(for: track, raw: lyricsText)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SpotifyInspiredBackground: View {
    let data: Data?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                Group {
                    if let data, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(x: -1, y: 1)
                    } else {
                        LinearGradient(colors: [.blue.opacity(0.8), .black], startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .blur(radius: 55)
                .scaleEffect(1.28)
                .opacity(0.72)
            }
            .ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.38), .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

struct FullLyricsView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if p.current?.lyrics.isEmpty != false {
                    VStack(spacing: 14) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("No synced lyrics")
                            .font(.title2.bold())
                        Text("Search timestamped lyrics or import an LRC file.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                ForEach(p.current?.lyrics ?? []) { line in
                                    let active = isActive(line)
                                    Text(line.text.isEmpty ? "♪" : line.text)
                                        .font(active ? .title.bold() : .title2.weight(.semibold))
                                        .foregroundStyle(active ? .white : .white.opacity(0.35))
                                        .id(line.id)
                                        .onTapGesture { p.seek(line.time) }
                                }
                            }
                            .padding(24)
                            .padding(.bottom, 80)
                        }
                        .onChange(of: p.time) { newTime in
                            if let line = (p.current?.lyrics ?? []).last(where: { $0.time <= newTime }) {
                                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(line.id, anchor: .center) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func isActive(_ line: LyricLine) -> Bool {
        guard let lines = p.current?.lyrics, let index = lines.firstIndex(of: line) else { return false }
        let next = index + 1 < lines.count ? lines[index + 1].time : Double.greatestFiniteMagnitude
        return line.time <= p.time && p.time < next
    }
}

// MARK: - Dedicated LRC picker
// Use the legacy document-type initializer with public.data/public.text.
// Some Files providers expose .lrc using a dynamic/subtitle UTI and SwiftUI's
// fileImporter leaves those files visible but disabled. public.data lets iOS
// hand the file to Musix; attachLRC then validates/parses the contents.
private struct LRCFilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.text"], in: .import)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onCancel(); return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

struct PlayerSettingsView: View {
    @EnvironmentObject var p: PlayerModel
    @Binding var showLyricSearch: Bool
    @Binding var showLRCImporter: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Toggle("Shuffle", isOn: $p.shuffle)
                    Picker("Repeat", selection: $p.repeatMode) {
                        ForEach(RepeatMode.allCases, id: \.self) { mode in Text(mode.rawValue.capitalized).tag(mode) }
                    }
                    Picker("Playback Speed", selection: Binding(get: { p.speed }, set: { p.setRate($0) })) {
                        Text("0.75×").tag(Float(0.75)); Text("1×").tag(Float(1)); Text("1.25×").tag(Float(1.25)); Text("1.5×").tag(Float(1.5)); Text("2×").tag(Float(2))
                    }
                    Picker("Sleep Timer", selection: Binding(get: { p.sleepMinutes }, set: { p.setSleep($0) })) {
                        Text("Off").tag(0); Text("15 min").tag(15); Text("30 min").tag(30); Text("45 min").tag(45); Text("60 min").tag(60)
                    }
                }
                Section("Lyrics") {
                    Toggle("Floating Lyrics", isOn: $p.floatingLyrics)
                    Button("Search Synced Lyrics") { showLyricSearch = true }
                    Button("Import LRC File") { showLRCImporter = true }
                }
            }
            .navigationTitle("Player Settings")
        }
    }
}

struct MusicInfoView: View {
    @EnvironmentObject var p: PlayerModel
    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Title", value: p.current?.title ?? "—")
                LabeledContent("Artist", value: p.current?.artist ?? "—")
                LabeledContent("Album", value: p.current?.album ?? "—")
                LabeledContent("File", value: p.current?.url.lastPathComponent ?? "—")
                LabeledContent("Duration", value: String(format: "%.0f sec", p.duration))
            }
            .navigationTitle("Music Info")
        }
    }
}

struct SyncedLyricsSearchView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if p.lyricsSearching {
                    ProgressView("Searching timestamped lyrics…")
                } else if !p.lyricSearchResults.isEmpty {
                    List(p.lyricSearchResults) { result in
                        Button {
                            p.applyLyrics(result)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.trackName).font(.headline)
                                Text(result.artistName + (result.albumName.map { " • " + $0 } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Label("Synced / timestamped", systemImage: "waveform")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text(p.lyricsError ?? "Find synced lyrics")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("Searches by the current song title and artist.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle("Search Lyrics")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Search") { Task { await p.searchSyncedLyrics() } } } }
            .task { if p.lyricSearchResults.isEmpty { await p.searchSyncedLyrics() } }
        }
    }
}

// Scrolls only when a metadata field is wider than its available space.
// Keeping this separate avoids changing the existing Now Playing vertical layout.
private struct MusixMarqueeText: View {
    let text: String
    let fontSize: CGFloat
    let weight: UIFont.Weight
    let color: UIColor
    var centered: Bool = false
    @State private var cycleStart = Date()

    private var measuredWidth: CGFloat {
        (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: weight)]).width + 5
    }

    var body: some View {
        GeometryReader { geometry in
            let overflow = max(0, measuredWidth - geometry.size.width)
            // Short text stays still. Long text always travels right-to-left,
            // pauses, then resets to the start (never reverses direction).
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: overflow <= 1)) { context in
                let travel = max(3.0, Double(overflow) / 25.0)
                let cycle = 1.2 + travel + 1.0
                let elapsed = max(0, context.date.timeIntervalSince(cycleStart))
                let phase = elapsed.truncatingRemainder(dividingBy: cycle)
                let offset = overflow <= 1 ? 0 : CGFloat(min(1, max(0, (phase - 1.2) / travel))) * overflow
                Text(text)
                    .font(.system(size: fontSize, weight: swiftWeight))
                    .foregroundStyle(Color(uiColor: color))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: geometry.size.width, height: geometry.size.height,
                           alignment: centered && overflow <= 1 ? .center : .leading)
                    .offset(x: -offset)
                    .clipped()
            }
            .onChange(of: text) { _ in cycleStart = Date() }
            .onChange(of: geometry.size.width) { _ in cycleStart = Date() }
        }
        .accessibilityLabel(text)
    }

    private var swiftWeight: Font.Weight {
        if weight == .bold { return .bold }
        if weight == .semibold { return .semibold }
        return .regular
    }
}
