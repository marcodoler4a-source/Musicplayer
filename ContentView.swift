import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var selection = 0
    @State private var showNowPlaying = false
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                HomeView().tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
                LibraryView().tabItem { Label("Library", systemImage: "books.vertical.fill") }.tag(2)
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(3)
            }
            if player.currentTrack != nil { MiniPlayer(showNowPlaying: $showNowPlaying).padding(.bottom, 49) }
        }
        .tint(.green)
        .sheet(isPresented: $showNowPlaying) { NowPlayingView() }
    }
}

struct HomeView: View {
    @EnvironmentObject var player: AudioPlayerManager
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(greeting).font(.largeTitle.bold())
                    if !player.tracks.filter({$0.isFavorite}).isEmpty {
                        NavigationLink { TrackListView(title: "Liked Songs", tracks: player.tracks.filter{$0.isFavorite}) } label: { Label("Liked Songs", systemImage: "heart.fill").font(.title2.bold()).foregroundStyle(.white) }
                    }
                    Text("Recently added").font(.title2.bold())
                    ForEach(player.tracks.sorted{$0.dateAdded > $1.dateAdded}.prefix(6)) { TrackRow(track: $0) }
                    Text("Your music").font(.title2.bold())
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 16) { ForEach(player.tracks) { t in VStack(alignment: .leading) { ArtworkView(track: t).frame(width: 155, height: 155); Text(t.title).bold().lineLimit(1); Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }.frame(width: 155).onTapGesture { player.play(t) } } } }
                }.padding().padding(.bottom, 110)
            }.background(LinearGradient(colors: [.green.opacity(0.28), .black, .black], startPoint: .top, endPoint: .center)).navigationTitle("Melo").navigationBarTitleDisplayMode(.inline)
        }
    }
    var greeting: String { let h = Calendar.current.component(.hour, from: Date()); return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening" }
}

struct SearchView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var query = ""
    var filtered: [Track] { query.isEmpty ? player.tracks : player.tracks.filter { ($0.title + $0.artist + $0.album).localizedCaseInsensitiveContains(query) } }
    var body: some View { NavigationStack { List(filtered) { TrackRow(track: $0) }.searchable(text: $query, prompt: "Songs, artists or albums").navigationTitle("Search") } }
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
            }.navigationTitle("Your Library").toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Picker("Sort", selection: $sort) { ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down") } } }
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
        ZStack { LinearGradient(colors: [.green.opacity(0.45), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea(); ScrollView { VStack(spacing: 22) {
            HStack { Button { dismiss() } label: { Image(systemName: "chevron.down") }; Spacer(); Text("NOW PLAYING").font(.caption.bold()); Spacer(); Menu { Button("Edit song") { editing = true }; Button("Lyrics") { showLyrics = true }; if let id = player.currentTrack?.id { Button(player.currentTrack?.isFavorite == true ? "Unlike" : "Like") { player.toggleFavorite(id) } } } label: { Image(systemName: "ellipsis") } }
            if let t = player.currentTrack { ArtworkView(track: t).aspectRatio(1, contentMode: .fit).shadow(radius: 25) }
            HStack { VStack(alignment: .leading) { Text(player.currentTrack?.title ?? "Select a song").font(.title2.bold()); Text(player.currentTrack?.artist ?? "").foregroundStyle(.secondary) }; Spacer(); if let id = player.currentTrack?.id { Button { player.toggleFavorite(id) } label: { Image(systemName: player.currentTrack?.isFavorite == true ? "heart.fill" : "heart").font(.title2) } } }
            Slider(value: Binding(get: { player.progress }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1)); HStack { Text(format(player.progress)); Spacer(); Text("-" + format(max(player.duration-player.progress,0))) }.font(.caption).foregroundStyle(.secondary)
            HStack { Button { player.isShuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.isShuffle ? .green : .white) }; Spacer(); Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title) }; Spacer(); Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 70)) }; Spacer(); Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title) }; Spacer(); Button { player.setRepeatNext() } label: { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(player.repeatMode == .off ? .white : .green) } }.buttonStyle(.plain)
            HStack { Image(systemName: "speaker.fill"); Slider(value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }), in: 0...1); Image(systemName: "speaker.wave.3.fill") }
            if player.showLyricsCard, let t = player.currentTrack { Button { showLyrics = true } label: { VStack(alignment: .leading, spacing: 12) { HStack { Text("Lyrics").font(.title2.bold()); Spacer(); Image(systemName: "arrow.up.left.and.arrow.down.right") }; Text(t.lyrics.isEmpty ? "Tap to search, paste, or edit lyrics." : t.lyrics).lineLimit(7).multilineTextAlignment(.leading) }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white) } }
        }.padding(24).padding(.bottom, 20) } }
        .sheet(isPresented: $editing) { if let id = player.currentTrack?.id { EditTrackView(trackID: id) } }
        .sheet(isPresented: $showLyrics) { if let id = player.currentTrack?.id { LyricsView(trackID: id) } }
    }
    private func format(_ x: Double) -> String { let s = Int(x); return String(format: "%d:%02d", s/60, s%60) }
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
    var track: Track? { player.tracks.first{$0.id == trackID} }
    var body: some View { NavigationStack { VStack(spacing: 12) { TextEditor(text: $text).font(.title3).padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)); if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }; Button { Task { await searchLyrics() } } label: { Label(searching ? "Searching…" : "Search Lyrics Online", systemImage: "magnifyingglass").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent).disabled(searching) }.padding().navigationTitle("Lyrics").toolbar { ToolbarItem(placement:.cancellationAction){Button("Close"){dismiss()}}; ToolbarItem(placement:.confirmationAction){Button("Save"){ save(); dismiss() }.bold()} }.onAppear { text = track?.lyrics ?? "" } } }
    private func save() { guard var t=track else{return}; t.lyrics=text; player.updateTrack(t) }
    private func searchLyrics() async { guard let t=track else{return}; searching=true; defer{searching=false}; var c=URLComponents(string:"https://lrclib.net/api/get")!; c.queryItems=[URLQueryItem(name:"track_name",value:t.title),URLQueryItem(name:"artist_name",value:t.artist),URLQueryItem(name:"album_name",value:t.album)]; guard let u=c.url, let(data,r)=try? await URLSession.shared.data(from:u), (r as? HTTPURLResponse)?.statusCode==200, let j=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {message="No matching lyrics found. You can paste or type lyrics manually.";return}; if let p=j["plainLyrics"] as? String,!p.isEmpty{text=p;message="Lyrics found. Review them, then tap Save."}else if let s=j["syncedLyrics"] as? String{text=s;message="Synced lyrics found. Tap Save."}else{message="No lyrics text was returned."} }
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
