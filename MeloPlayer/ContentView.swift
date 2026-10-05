import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var selection = 0
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            Group {
                switch selection {
                case 0: HomeView()
                case 1: SearchView()
                case 2: LibraryView()
                default: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                if player.currentTrack != nil { MiniPlayer(showNowPlaying: $showNowPlaying) }
                MeloTabBar(selection: $selection)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .tint(.green)
        .fullScreenCover(isPresented: $showNowPlaying) { NowPlayingView() }
    }
}

struct MeloTabBar: View {
    @Binding var selection: Int
    private let tabs = [("Home","house.fill"),("Search","magnifyingglass"),("Library","books.vertical.fill"),("Settings","gearshape.fill")]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { i in
                Button { selection = i } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tabs[i].1).font(.system(size: 20, weight: .semibold))
                        Text(tabs[i].0).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selection == i ? Color.green : Color.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selection == i ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

struct HomeView: View {
    @EnvironmentObject var player: AudioPlayerManager
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Melo").font(.system(size: 28, weight: .bold)); Spacer(); Image(systemName: "gearshape").font(.system(size: 18)) }
                    .padding(.top, 8)
                Text(greeting).font(.system(size: 32, weight: .bold))
                HStack { Text("Recently added").font(.system(size: 20, weight: .bold)); Spacer(); Text("See all").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green) }
                if player.tracks.isEmpty {
                    ContentUnavailableView("No music yet", systemImage: "music.note", description: Text("Import songs from Library."))
                        .frame(maxWidth: .infinity).padding(.top, 50)
                } else {
                    ForEach(player.tracks.sorted{$0.dateAdded > $1.dateAdded}.prefix(8)) { TrackRow(track: $0) }
                    Text("Your music").font(.system(size: 20, weight: .bold)).padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) { ForEach(player.tracks) { t in
                            VStack(alignment: .leading, spacing: 5) {
                                ArtworkView(track: t).frame(width: 142, height: 142)
                                Text(t.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(t.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 142).onTapGesture { player.play(t) }
                        } }
                    }
                }
            }.padding(.horizontal, 18).padding(.bottom, 155)
        }
        .background(LinearGradient(colors: [.green.opacity(0.30), .black, .black], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }
    var greeting: String { let h = Calendar.current.component(.hour, from: Date()); return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening" }
}

struct SearchView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var query = ""
    var filtered: [Track] { query.isEmpty ? player.tracks : player.tracks.filter { ($0.title + $0.artist + $0.album).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List(filtered) { TrackRow(track: $0) }
                .scrollContentBackground(.hidden).background(Color.black)
                .searchable(text: $query, prompt: "Songs, artists or albums")
                .navigationTitle("Search")
                .safeAreaPadding(.bottom, 125)
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var importing = false
    @State private var showNewPlaylist = false
    @State private var playlistName = ""
    @State private var sort: SortMode = .newest
    @State private var importError: String?
    var sorted: [Track] { switch sort { case .newest: return player.tracks.sorted{$0.dateAdded > $1.dateAdded}; case .title: return player.tracks.sorted{$0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending}; case .artist: return player.tracks.sorted{$0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending}; case .mostPlayed: return player.tracks.sorted{$0.playCount > $1.playCount} } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { importing = true } label: { Label("Import audio from Files", systemImage: "square.and.arrow.down") }
                    Button { showNewPlaylist = true } label: { Label("New Playlist", systemImage: "text.badge.plus") }
                    NavigationLink { TrackListView(title: "Liked Songs", tracks: player.tracks.filter{$0.isFavorite}) } label: { Label("Liked Songs", systemImage: "heart.fill") }
                }
                if !player.playlists.isEmpty { Section("Playlists") { ForEach(player.playlists) { p in NavigationLink { PlaylistView(playlistID: p.id) } label: { Label(p.name, systemImage: "music.note.list") } }.onDelete { offsets in offsets.map { player.playlists[$0].id }.forEach(player.deletePlaylist) } } }
                Section("Songs") { ForEach(sorted) { TrackRow(track: $0) } }
            }
            .scrollContentBackground(.hidden).background(Color.black)
            .safeAreaPadding(.bottom, 125)
            .navigationTitle("Library")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Picker("Sort", selection: $sort) { ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down") } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in do { for u in try result.get() { try player.importAudio(from: u) } } catch { importError = error.localizedDescription } }
            .alert("New Playlist", isPresented: $showNewPlaylist) { TextField("Playlist name", text: $playlistName); Button("Create") { player.createPlaylist(name: playlistName); playlistName = "" }; Button("Cancel", role: .cancel) {} }
            .alert("Import Failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) { Button("OK") {} } message: { Text(importError ?? "") }
        }
    }
}

struct TrackRow: View {
    @EnvironmentObject var player: AudioPlayerManager
    let track: Track
    @State private var editing = false
    var body: some View {
        HStack(spacing: 12) { Button { player.play(track) } label: { HStack(spacing: 12) { ArtworkView(track: track).frame(width: 54, height: 54); VStack(alignment: .leading) { Text(track.title).foregroundStyle(.primary).font(.headline).lineLimit(1); Text(track.artist).foregroundStyle(.secondary).font(.subheadline).lineLimit(1) }; Spacer() } }.buttonStyle(.plain)
            Menu { Button { player.toggleFavorite(track.id) } label: { Label(track.isFavorite ? "Unlike" : "Like", systemImage: track.isFavorite ? "heart.slash" : "heart") }; Button { editing = true } label: { Label("Edit Song", systemImage: "pencil") }; if !player.playlists.isEmpty { Menu("Add to Playlist") { ForEach(player.playlists) { p in Button(p.name) { player.addTrack(track.id, to: p.id) } } } }; Button(role: .destructive) { player.deleteTrack(track.id) } label: { Label("Delete from Library", systemImage: "trash") } } label: { Image(systemName: "ellipsis").padding(8) }
        }.sheet(isPresented: $editing) { EditTrackView(trackID: track.id) }
    }
}

struct ArtworkView: View {
    let track: Track
    var body: some View { Group { if let name = track.artworkFileName, let ui = UIImage(contentsOfFile: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name).path) { Image(uiImage: ui).resizable().scaledToFill() } else { RoundedRectangle(cornerRadius: 7).fill(.gray.opacity(0.25)).overlay(Image(systemName: track.artwork).font(.title2)) } }.clipShape(RoundedRectangle(cornerRadius: 7)) }
}

struct MiniPlayer: View {
    @EnvironmentObject var player: AudioPlayerManager
    @Binding var showNowPlaying: Bool
    var body: some View { Button { showNowPlaying = true } label: { HStack { if let t = player.currentTrack { ArtworkView(track: t).frame(width: 46, height: 46) }; VStack(alignment: .leading) { Text(player.currentTrack?.title ?? "").bold().lineLimit(1); Text(player.currentTrack?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2) }.buttonStyle(.plain) }.padding(8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8) }.buttonStyle(.plain) }
}

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var editing = false
    @State private var showLyrics = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                nowPlayingBackground
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)) }
                        Spacer()
                        Text("NOW PLAYING").font(.system(size: 11, weight: .bold)).tracking(1.2)
                        Spacer()
                        Button { editing = true } label: { Image(systemName: "pencil").font(.system(size: 16, weight: .semibold)) }
                    }
                    .frame(height: 42)

                    if let t = player.currentTrack {
                        ArtworkView(track: t)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: min(geo.size.width - 42, geo.size.height * 0.39))
                            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                            .padding(.top, 4)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(player.currentTrack?.title ?? "Select a song").font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                            Text(player.currentTrack?.artist ?? "").font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if let id = player.currentTrack?.id {
                            Button { player.toggleFavorite(id) } label: { Image(systemName: player.currentTrack?.isFavorite == true ? "heart.fill" : "heart").font(.system(size: 20)) }
                        }
                    }.padding(.top, 16)

                    VStack(spacing: 5) {
                        Slider(value: Binding(get: { player.progress }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1))
                        HStack { Text(format(player.progress)); Spacer(); Text("-" + format(max(player.duration-player.progress,0))) }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.top, 10)

                    HStack {
                        Button { player.isShuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.isShuffle ? .green : .white) }
                        Spacer()
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 23)) }
                        Spacer()
                        Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 58)) }
                        Spacer()
                        Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 23)) }
                        Spacer()
                        Button { player.setRepeatNext() } label: { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(player.repeatMode == .off ? .white : .green) }
                    }.buttonStyle(.plain).padding(.vertical, 8)

                    if player.showLyricsCard, let t = player.currentTrack {
                        SyncedLyricsCard(track: t)
                            .frame(maxHeight: .infinity)
                            .onTapGesture { showLyrics = true }
                    } else { Spacer(minLength: 4) }
                }
                .padding(.horizontal, 21)
                .padding(.top, max(geo.safeAreaInsets.top, 8))
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 8))
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $editing) { if let id = player.currentTrack?.id { EditTrackView(trackID: id) } }
        .sheet(isPresented: $showLyrics) { if let id = player.currentTrack?.id { LyricsView(trackID: id) } }
    }

    @ViewBuilder private var nowPlayingBackground: some View {
        if let t = player.currentTrack, let name = t.artworkFileName,
           let ui = UIImage(contentsOfFile: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name).path) {
            Image(uiImage: ui).resizable().scaledToFill().blur(radius: 42).scaleEffect(1.15).overlay(.black.opacity(0.55)).ignoresSafeArea()
        } else {
            LinearGradient(colors: [.green.opacity(0.35), .black, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        }
    }
    private func format(_ x: Double) -> String { let s = Int(x); return String(format: "%d:%02d", s/60, s%60) }
}

struct SyncedLyricsCard: View {
    @EnvironmentObject var player: AudioPlayerManager
    let track: Track
    private var lines: [LRCLine] { LRCParser.parse(track.lyrics) }
    private var active: Int? { LRCParser.activeIndex(in: lines, at: player.progress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text("Lyrics").font(.system(size: 15, weight: .bold)); Spacer(); Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12)) }
            if track.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Tap to search online or import an LRC file.").font(.system(size: 14)).foregroundStyle(.secondary)
            } else if !lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: i == active ? 18 : 15, weight: i == active ? .bold : .medium))
                                    .foregroundStyle(i == active ? .white : .white.opacity(0.46))
                                    .id(i)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .onChange(of: active) { _, value in
                        if let value { withAnimation(.easeInOut(duration: 0.28)) { proxy.scrollTo(value, anchor: .center) } }
                    }
                }
            } else {
                ScrollView(showsIndicators: false) { Text(LRCParser.plainText(from: track.lyrics)).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct EditTrackView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    let trackID: UUID
    @State private var draft: Track?
    @State private var photo: PhotosPickerItem?
    @State private var showLyrics = false
    var body: some View { NavigationStack { Form { if let d = draft { Section("Artwork") { HStack { Spacer(); ArtworkView(track: d).frame(width: 180, height: 180); Spacer() }; PhotosPicker(selection: $photo, matching: .images) { Label("Choose from Photos", systemImage: "photo") }; Button("Search Album Artwork") { Task { await searchAndSaveArtwork() } }; if d.artworkFileName != nil { Button("Remove Custom Artwork", role: .destructive) { removeArtwork() } } }; Section("Song information") { TextField("Title", text: binding(\.title)); TextField("Artist", text: binding(\.artist)); TextField("Album", text: binding(\.album)); TextField("Genre", text: binding(\.genre)); TextField("Year", value: bindingOptionalInt(\.year), format: .number) }; Section { Button("Edit Lyrics") { showLyrics = true }; LabeledContent("Play Count", value: "\(d.playCount)"); LabeledContent("File", value: d.filePath ?? "Bundled MP3") } } }.navigationTitle("Edit Song").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { if let draft { player.updateTrack(draft) }; dismiss() }.bold() } }.onAppear { draft = player.tracks.first{$0.id == trackID} }.onChange(of: photo) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { saveArtwork(data) } } }.sheet(isPresented: $showLyrics) { LyricsView(trackID: trackID) } } }
    private func binding(_ key: WritableKeyPath<Track,String>) -> Binding<String> { Binding(get: { draft?[keyPath:key] ?? "" }, set: { draft?[keyPath:key] = $0 }) }
    private func bindingOptionalInt(_ key: WritableKeyPath<Track,Int?>) -> Binding<Int?> { Binding(get: { draft?[keyPath:key] }, set: { draft?[keyPath:key] = $0 }) }
    private func saveArtwork(_ data: Data) { guard var d = draft else { return }; let name = "art_\(trackID.uuidString).jpg"; let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name); try? data.write(to: url); d.artworkFileName = name; draft = d }
    private func removeArtwork() { guard var d = draft else { return }; if let n = d.artworkFileName { try? FileManager.default.removeItem(at: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(n)) }; d.artworkFileName = nil; draft = d }
    private func searchAndSaveArtwork() async { guard let d = draft else { return }; let q = "\(d.artist) \(d.album == "Unknown Album" ? d.title : d.album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""; guard let url = URL(string: "https://itunes.apple.com/search?term=\(q)&entity=song&limit=1"), let (data,_) = try? await URLSession.shared.data(from:url), let obj = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let r = (obj["results"] as? [[String:Any]])?.first, var s = r["artworkUrl100"] as? String else { return }; s = s.replacingOccurrences(of: "100x100", with: "600x600"); if let u=URL(string:s), let (img,_) = try? await URLSession.shared.data(from:u) { saveArtwork(img) } }
}

struct LyricsView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    let trackID: UUID
    @State private var text = ""
    @State private var searching = false
    @State private var message = ""
    @State private var importingLRC = false
    var track: Track? { player.tracks.first{$0.id == trackID} }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if !LRCParser.parse(text).isEmpty {
                    Label("Timed LRC detected — lyrics will follow playback.", systemImage: "waveform.badge.checkmark").font(.system(size: 12)).foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading)
                }
                TextEditor(text: $text).font(.system(size: 15)).padding(7).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Button { importingLRC = true } label: { Label("Import LRC", systemImage: "doc.badge.plus") }.buttonStyle(.bordered)
                    Button { Task { await searchLyrics() } } label: { Label(searching ? "Searching…" : "Search Online", systemImage: "magnifyingglass") }.buttonStyle(.borderedProminent).disabled(searching)
                }
            }
            .padding(14)
            .navigationTitle("Lyrics").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction){Button("Close"){dismiss()}}; ToolbarItem(placement:.confirmationAction){Button("Save"){ save(); dismiss() }.bold()} }
            .onAppear { text = track?.lyrics ?? "" }
            .fileImporter(isPresented: $importingLRC, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    text = try String(contentsOf: url, encoding: .utf8)
                    message = LRCParser.parse(text).isEmpty ? "File imported, but no LRC timestamps were found." : "Timed LRC imported successfully."
                } catch { message = "Could not read that LRC file: \(error.localizedDescription)" }
            }
        }
    }
    private func save() { guard var t=track else{return}; t.lyrics=text; player.updateTrack(t) }
    private func searchLyrics() async {
        guard let t = track else { return }
        searching = true; defer { searching = false }
        let cleanTitle = t.title.replacingOccurrences(of: #"\s*[\(\[].*?(remaster|live|official|video|lyrics|version).*?[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
        let attempts: [(String,String?)] = [(t.title,t.artist),(cleanTitle,t.artist),(cleanTitle,nil)]
        for (title, artist) in attempts {
            var c = URLComponents(string: "https://lrclib.net/api/search")!
            var items = [URLQueryItem(name:"track_name", value:title)]
            if let artist, !artist.isEmpty { items.append(URLQueryItem(name:"artist_name", value:artist)) }
            c.queryItems = items
            guard let url = c.url else { continue }
            var req = URLRequest(url:url); req.setValue("MeloPlayer/2.0", forHTTPHeaderField:"User-Agent")
            guard let (data,response) = try? await URLSession.shared.data(for:req), (response as? HTTPURLResponse)?.statusCode == 200,
                  let rows = try? JSONSerialization.jsonObject(with:data) as? [[String:Any]] else { continue }
            if let row = rows.first(where: { (($0["syncedLyrics"] as? String)?.isEmpty == false) }), let synced = row["syncedLyrics"] as? String {
                text = synced; message = "Synced lyrics found. Tap Save."; return
            }
            if let row = rows.first, let plain = row["plainLyrics"] as? String, !plain.isEmpty {
                text = plain; message = "Lyrics found, but this result has no timestamps."; return
            }
        }
        message = "No lyrics found online. Try editing the title/artist or import an .lrc file."
    }
}

struct PlaylistView: View {
    @EnvironmentObject var player: AudioPlayerManager
    let playlistID: UUID
    var playlist: Playlist? { player.playlists.first{$0.id == playlistID} }
    var body: some View { List { if let p=playlist { ForEach(player.tracks(in:p)) { t in TrackRow(track:t).swipeActions { Button(role:.destructive){player.removeTrack(t.id,from:p.id)}label:{Label("Remove",systemImage:"minus.circle")} } } } }.navigationTitle(playlist?.name ?? "Playlist") }
}

struct TrackListView: View { let title:String; let tracks:[Track]; var body: some View { List(tracks){TrackRow(track:$0)}.navigationTitle(title) } }

struct SettingsView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var confirmReset = false
    var body: some View { NavigationStack { Form {
        Section("Playback") { Toggle("Shuffle", isOn:$player.isShuffle); Picker("Repeat",selection:$player.repeatMode){Text("Off").tag(RepeatMode.off);Text("All").tag(RepeatMode.all);Text("One").tag(RepeatMode.one)}; Picker("Playback Speed",selection:$player.playbackRate){Text("0.75×").tag(Float(0.75));Text("1×").tag(Float(1));Text("1.25×").tag(Float(1.25));Text("1.5×").tag(Float(1.5));Text("2×").tag(Float(2))}; Toggle("Remember playback position",isOn:$player.rememberPosition); Toggle("Crossfade preference",isOn:$player.crossfadeEnabled) }
        Section("Player") { Toggle("Haptic feedback",isOn:$player.hapticsEnabled); Toggle("Show floating lyrics",isOn:$player.showLyricsCard); Picker("Accent",selection:$player.accentChoice){Text("Green").tag("Green");Text("Blue").tag("Blue");Text("Purple").tag("Purple")} }
        Section("Sleep Timer") { Button("15 minutes"){player.setSleepTimer(minutes:15)}; Button("30 minutes"){player.setSleepTimer(minutes:30)}; Button("60 minutes"){player.setSleepTimer(minutes:60)}; if player.sleepTimerEnd != nil { Button("Cancel Sleep Timer",role:.destructive){player.setSleepTimer(minutes:nil)} } }
        Section("Library") { LabeledContent("Songs",value:"\(player.tracks.count)"); LabeledContent("Playlists",value:"\(player.playlists.count)"); LabeledContent("Favorites",value:"\(player.tracks.filter{$0.isFavorite}.count)") }
        Section("Reset") { Button("Reset Settings"){player.resetSettings()}; Button("Reset Library",role:.destructive){confirmReset=true} }
        Section("About") { LabeledContent("App",value:"Melo"); LabeledContent("Version",value:"1.1") }
    }.navigationTitle("Settings").alert("Reset Library?",isPresented:$confirmReset){Button("Reset",role:.destructive){player.resetLibrary()};Button("Cancel",role:.cancel){}} message:{Text("This removes the app library and playlists. Imported audio files may also be removed when individually deleted.")} } }
}
