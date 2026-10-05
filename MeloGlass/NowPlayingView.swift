import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var lrc = false
    @State private var info = false
    @State private var lyricSearch = false

    var body: some View {
        ZStack {
            BackgroundArt(data: p.current?.artworkData)
            Rectangle().fill(.black.opacity(0.35)).ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                    Spacer()
                    Text("NOW PLAYING").font(.caption.bold())
                    Spacer()
                    Button { info = true } label: { Image(systemName: "info.circle") }
                }
                .padding(.horizontal)

                Picker("View", selection: $tab) {
                    Text("Player").tag(0)
                    Text("Lyrics").tag(1)
                    Text("Settings").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    if tab == 0 { player }
                    else if tab == 1 { lyrics }
                    else { settings }
                }
                Spacer(minLength: 8)
            }
            .padding(.top)
        }
        .fileImporter(isPresented: $lrc, allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText]) { result in
            if case .success(let url) = result {
                let accessed = url.startAccessingSecurityScopedResource()
                p.attachLRC(url: url)
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
        }
        .sheet(isPresented: $info) { MusicInfoView().environmentObject(p) }
        .sheet(isPresented: $lyricSearch) { SyncedLyricsSearchView().environmentObject(p) }
    }

    private var player: some View {
        VStack(spacing: 18) {
            Artwork(data: p.current?.artworkData)
                .frame(maxWidth: 330)
                .aspectRatio(1, contentMode: .fit)
                .shadow(radius: 30)
                .padding(.top, 12)

            VStack {
                Text(p.current?.title ?? "Unknown").font(.title2.bold()).lineLimit(1)
                Text(p.current?.artist ?? "Unknown Artist").foregroundStyle(.secondary)
            }

            Slider(value: Binding(get: { p.time }, set: { p.seek($0) }), in: 0...max(1, p.duration))

            HStack {
                Text(fmt(p.time))
                Spacer()
                Text("-" + fmt(max(0, p.duration - p.time)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 36) {
                Button { p.shuffle.toggle() } label: {
                    Image(systemName: "shuffle").foregroundStyle(p.shuffle ? .blue : .white)
                }
                Button { p.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                Button { p.toggle() } label: {
                    Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 66))
                }
                Button { p.next() } label: { Image(systemName: "forward.fill").font(.title) }
                Button {
                    p.repeatMode = p.repeatMode == .off ? .all : (p.repeatMode == .all ? .one : .off)
                } label: {
                    Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(p.repeatMode == .off ? .white : .blue)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var lyrics: some View {
        VStack {
            HStack {
                Text("Synced Lyrics").font(.title2.bold())
                Spacer()
                Button { lyricSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
                Button("LRC") { lrc = true }
            }
            .padding(.horizontal)

            if p.current?.lyrics.isEmpty != false {
                ContentUnavailableView("No lyrics loaded", systemImage: "quote.bubble", description: Text("Load an .lrc file or search for timestamped lyrics."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(p.current?.lyrics ?? []) { line in
                                let active = activeLyric(line)
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(active ? .title2.bold() : .title3)
                                    .foregroundStyle(active ? .white : .white.opacity(0.45))
                                    .id(line.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: p.time) { _, newTime in
                        if let line = (p.current?.lyrics ?? []).last(where: { $0.time <= newTime }) {
                            withAnimation { proxy.scrollTo(line.id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var settings: some View {
        Form {
            Section("Playback") {
                Toggle("Shuffle", isOn: $p.shuffle)
                Picker("Repeat", selection: $p.repeatMode) {
                    ForEach(RepeatMode.allCases, id: \.self) { Text($0.rawValue.capitalized) }
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
                Button("Search Synced Lyrics") { lyricSearch = true }
                Button("Import LRC file") { lrc = true }
                Text("Synced lyrics use timestamps and automatically follow the song position.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio") {
                Text("Background playback, Lock Screen controls, Control Center metadata and AirPlay are enabled.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func activeLyric(_ line: LRCLine) -> Bool {
        guard let lines = p.current?.lyrics, let index = lines.firstIndex(of: line) else { return false }
        let nextTime = index + 1 < lines.count ? lines[index + 1].time : .greatestFiniteMagnitude
        return line.time <= p.time && p.time < nextTime
    }

    private func fmt(_ x: Double) -> String {
        let s = max(0, Int(x)); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct BackgroundArt: View {
    let data: Data?
    var body: some View {
        GeometryReader { g in
            Group {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().scaleEffect(x: -1, y: 1)
                } else {
                    LinearGradient(colors: [.blue, .black], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped().blur(radius: 45).scaleEffect(1.18).opacity(0.7)
        }
        .ignoresSafeArea()
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
                if let track = p.current {
                    let q = (track.title + " " + track.artist).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://musicbrainz.org/search?query=\(q)&type=recording&method=indexed") {
                        Link("Search music info", destination: url)
                    }
                }
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
                            p.applyLyrics(result); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.trackName).font(.headline)
                                Text(result.artistName + (result.albumName.map { " • " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
                                Label("Synced / timestamped", systemImage: "waveform").font(.caption).foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ContentUnavailableView(p.lyricsError ?? "Find synced lyrics", systemImage: "text.magnifyingglass", description: Text("Searches by the current song title and artist. Choose a timestamped result to sync it with playback."))
                }
            }
            .navigationTitle("Search Lyrics")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Search") { Task { await p.searchSyncedLyrics() } } } }
            .task { if p.lyricSearchResults.isEmpty { await p.searchSyncedLyrics() } }
        }
    }
}
