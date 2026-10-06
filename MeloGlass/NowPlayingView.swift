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
    @State private var showSettings = false
    @State private var showArtworkMenu = false
    @State private var showTagEditor = false
    @State private var lyricsCollapsed = false
    @AppStorage("showLyricsOverlay") private var showLyricsOverlay = true

    var body: some View {
        ZStack {
            SpotifyInspiredBackground(data: p.current?.artworkData)

            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        topBar
                        artwork(maxWidth: min(geometry.size.width - 44, geometry.size.height * 0.43))
                        trackDetails
                        lyricsPanel
                        progress
                        playbackControls
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showLRCImporter,
            allowedContentTypes: [.data, .plainText, UTType(filenameExtension: "lrc") ?? .plainText]
        ) { result in
            if case .success(let url) = result {
                let accessed = url.startAccessingSecurityScopedResource()
                p.attachLRC(url: url)
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
        }
        .sheet(isPresented: $showInfo) { MusicInfoView().environmentObject(p) }
        .sheet(isPresented: $showLyricSearch) { SyncedLyricsSearchView().environmentObject(p) }
        .sheet(isPresented: $showMusicInfoSearch) { MusicInfoSearchView(target: p.current).environmentObject(p) }
        .sheet(isPresented: $showLyrics) { FullLyricsView().environmentObject(p) }
        .sheet(isPresented: $showSettings) { PlayerSettingsView(showLyricSearch: $showLyricSearch, showLRCImporter: $showLRCImporter).environmentObject(p) }
        .sheet(isPresented: $showTagEditor) { if let track=p.current { EditAudioTagView(track:track).environmentObject(p) } }
        .confirmationDialog("Song Options", isPresented: $showArtworkMenu, titleVisibility: .visible) {
            Button("Edit Audio Tag") { showTagEditor = true }
            Button("Search Music Info") { showMusicInfoSearch = true }
            Button("Add LRC") { showLRCImporter = true }
            Button("Search Lyrics") { showLyricSearch = true }
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
                Text(p.current?.album.isEmpty == false ? (p.current?.album ?? "Musix") : "Musix")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
            Button { showInfo = true } label: {
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
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    private var lyricsPanel: some View {
        Group {
            if showLyricsOverlay {
                if lyricsCollapsed {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { lyricsCollapsed = false }
                        } label: {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 42, height: 38)
                                .background(.white.opacity(0.10), in: Capsule())
                        }
                        .accessibilityLabel("Show lyrics")
                    }
                } else {
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
                                .frame(maxWidth: .infinity)
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
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { lyricsCollapsed = true }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 28)
                                .background(.black.opacity(0.18), in: Circle())
                        }
                        .offset(x: 8, y: -8)
                        .accessibilityLabel("Hide lyrics")
                    }
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10)))
                }
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private var trackDetails: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(p.current?.title ?? "Choose a song")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                Text(p.current?.artist ?? "Unknown Artist")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            Button {
                if let track = p.current { p.toggleFavorite(track) }
            } label: {
                Image(systemName: p.current.map { p.isFavorite($0) } == true ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(p.current.map { p.isFavorite($0) } == true ? Color.cyan : Color.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(p.current == nil)
        }
    }

    private var progress: some View {
        VStack(spacing: 5) {
            Slider(
                value: Binding(get: { p.time }, set: { p.seek($0) }),
                in: 0...max(1, p.duration)
            )
            .tint(.white)

            HStack {
                Text(formatTime(p.time))
                Spacer()
                Text("-" + formatTime(max(0, p.duration - p.time)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.top, 14)
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
        .padding(.top, 20)
        .padding(.bottom, 18)
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
    @State private var showArtworkImporter = false

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album)
        _genre = State(initialValue: track.genre)
        _releaseDate = State(initialValue: track.releaseDate)
        _trackNumber = State(initialValue: track.trackNumber)
        _artworkData = State(initialValue: track.artworkData)
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
            }
            .navigationTitle("Edit Audio Tag")
            .fileImporter(isPresented: $showArtworkImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), UIImage(data: data) != nil { artworkData = data }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        p.updateTag(for: track, title: title, artist: artist, album: album, genre: genre, releaseDate: releaseDate, trackNumber: trackNumber, artwork: artworkData)
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
                .frame(width: geometry.size.width, height: geometry.size.height * 0.68)
                .clipped()
                .blur(radius: 55)
                .scaleEffect(1.28)
                .opacity(0.72)
            }
            .ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.58), .black],
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
