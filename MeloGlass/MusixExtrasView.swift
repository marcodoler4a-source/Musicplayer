import SwiftUI

struct MusixExtrasView: View {
    @EnvironmentObject var p: PlayerModel
    @State private var name = ""
    @AppStorage("musixPlaylistFolders") private var folderData = "{}"
    @State private var newFolder = ""
    @State private var folderNames: [String] = []
    private var folderAssignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(folderData.utf8))) ?? [:]
    }
    private func assign(_ playlist: MusixPlaylist, to folder: String) {
        var map = folderAssignments
        if folder == "Unfiled" { map.removeValue(forKey: playlist.id.uuidString) }
        else { map[playlist.id.uuidString] = folder }
        if let data = try? JSONEncoder().encode(map), let value = String(data: data, encoding: .utf8) { folderData = value }
    }
    @AppStorage("musixFolderNames") private var savedFolders = "[]"
    private var folders: [String] { (try? JSONDecoder().decode([String].self, from: Data(savedFolders.utf8))) ?? [] }
    private func addFolder() {
        let value = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !folders.contains(value) else { return }
        if let data = try? JSONEncoder().encode(folders + [value]), let text = String(data: data, encoding: .utf8) { savedFolders = text }
        newFolder = ""
    }

    @State private var selectedPlaylist: UUID?
    @AppStorage("musixMoreSection") private var section = 5
    @State private var message = ""
    @State private var duplicates: [[Track]] = []
    @State private var showKaraoke = false
    @State private var showVisualizer = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // V78: Surface the restored features without hiding them in Tools.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        quickFeature("Settings", icon: "gearshape.fill", section: 5)
                        quickFeature("Backup & Restore", icon: "externaldrive", section: 3)
                        quickFeature("Duplicate Finder", icon: "doc.on.doc", section: 3)
                        quickFeature("Statistics", icon: "chart.bar", section: 2)
                        quickFeature("Dashboard", icon: "square.grid.2x2.fill", section: 4)
                        Button { showKaraoke = true } label: {
                            Label("Karaoke Lyrics", systemImage: "text.quote")
                        }.buttonStyle(.bordered)
                        quickFeature("Mini Player", icon: "rectangle.bottomthird.inset.filled", section: 3)
                        Button { showVisualizer = true } label: {
                            Label("Visualizer", systemImage: "waveform")
                        }.buttonStyle(.bordered)
                    }.padding(.horizontal).padding(.vertical, 10)
                }
                Picker("View", selection: $section) {
                    Text("Settings").tag(5)
                    Text("Playlists").tag(0)
                    Text("Up Next").tag(1)
                    Text("Statistics").tag(2)
                    Text("Tools").tag(3)
                    Text("Home").tag(4)
                }.pickerStyle(.segmented).padding()
                if section == 5 {
                    AppearanceSettingsView()
                } else {
                List {
                    if section == 4 {
                        Section("Your Library") {
                            HStack { Label("Songs", systemImage: "music.note"); Spacer(); Text("\(p.tracks.count)") }
                            HStack { Label("Artists", systemImage: "person.2"); Spacer(); Text("\(Set(p.tracks.map(\.artist)).count)") }
                            HStack { Label("Albums", systemImage: "square.stack"); Spacer(); Text("\(Set(p.tracks.map(\.album)).count)") }
                        }
                        Section("Recently Added") {
                            ForEach(Array(p.tracks.suffix(8).reversed())) { track in
                                Button { p.play(track, queue: p.tracks) } label: {
                                    HStack { Text(track.title).lineLimit(1); Spacer(); Image(systemName: "play.fill") }
                                }
                            }
                        }
                        Section("Most Played") {
                            ForEach(Array(p.smartTracks(.mostPlayed).prefix(8))) { track in
                                Button { p.play(track, queue: p.tracks) } label: {
                                    HStack { Text(track.title).lineLimit(1); Spacer(); Text("\(p.playCounts[track.id, default: 0]) plays").font(.caption) }
                                }
                            }
                        }
                    } else if section == 0 {
                        Section("Create playlist") {
                            HStack {
                                TextField("Playlist name", text: $name)
                                Button("Add") { p.createPlaylist(name); name = "" }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        Section("Smart Playlists · Auto-updating") {
                            ForEach(PlayerModel.SmartCollection.allCases) { collection in
                                NavigationLink {
                                    MusixSmartPlaylistDetail(collection: collection)
                                } label: {
                                    HStack {
                                        Image(systemName: "sparkles").foregroundStyle(.cyan)
                                        Text(collection.rawValue)
                                        Spacer()
                                        Text("\(p.smartTracks(collection).count)").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Section("Playlist Folders") {
                            HStack {
                                TextField("New folder", text: $newFolder)
                                Button("Create") { addFolder() }.disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            ForEach(folders, id: \.self) { folder in
                                NavigationLink {
                                    List {
                                        ForEach(p.playlists.filter { folderAssignments[$0.id.uuidString] == folder }) { playlist in
                                            NavigationLink(playlist.name) { MusixPlaylistDetail(playlistID: playlist.id) }
                                        }
                                    }.navigationTitle(folder)
                                } label: { Label(folder, systemImage: "folder.fill") }
                            }
                        }
                        ForEach(p.playlists) { playlist in
                            NavigationLink {
                                MusixPlaylistDetail(playlistID: playlist.id)
                            } label: {
                                HStack {
                                    Label(playlist.name, systemImage: "music.note.list")
                                    Spacer()
                                    Text(folderAssignments[playlist.id.uuidString] ?? "Unfiled").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button("Unfiled") { assign(playlist, to: "Unfiled") }
                                ForEach(folders, id: \.self) { folder in
                                    Button("Move to \(folder)") { assign(playlist, to: folder) }
                                }
                            }
                        }.onDelete { offsets in
                            for i in offsets { p.deletePlaylist(p.playlists[i].id) }
                        }
                    } else if section == 1 {
                        Section("Playback") {
                            Toggle("Stop after current song", isOn: $p.stopAfterCurrent)
                            Text("Use the ••• menu on a song to add it to Up Next.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Queued songs") {
                            ForEach(Array(p.upcomingTracks.enumerated()), id: \.offset) { index, track in
                                HStack { Text(track.title); Spacer(); Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                            }.onDelete { offsets in for i in offsets.sorted(by: >) { p.removeQueued(at: i) } }
                            .onMove { p.moveQueued(from: $0, to: $1) }
                        }
                    } else if section == 2 {
                        Section("Listening") {
                            Text("Listening time: \(Int(p.listeningSeconds / 3600))h \(Int(p.listeningSeconds / 60) % 60)m")
                            Text("Total plays: \(p.playCounts.values.reduce(0, +))")
                            Text("Unique artists: \(Set(p.tracks.map(\.artist)).count)")
                            Text("Albums: \(Set(p.tracks.map(\.album)).count)")
                            Section("Top Artists") {
                                ForEach(Array(Dictionary(grouping: p.tracks, by: \.artist).map { (name: $0.key, plays: $0.value.reduce(0) { $0 + p.playCounts[$1.id, default: 0] }) }.sorted { $0.plays > $1.plays }.prefix(10)), id: \.name) { item in
                                    HStack { Text(item.name); Spacer(); Text("\(item.plays) plays").foregroundStyle(.secondary) }
                                }
                            }
                            Section("Top Albums") {
                                ForEach(Array(Dictionary(grouping: p.tracks, by: \.album).map { (name: $0.key, plays: $0.value.reduce(0) { $0 + p.playCounts[$1.id, default: 0] }) }.sorted { $0.plays > $1.plays }.prefix(10)), id: \.name) { item in
                                    HStack { Text(item.name); Spacer(); Text("\(item.plays) plays").foregroundStyle(.secondary) }
                                }
                            }
                            Text("Songs played: \(p.playCounts.values.filter { $0 > 0 }.count)")
                            ForEach(p.tracks.sorted { p.playCounts[$0.id, default: 0] > p.playCounts[$1.id, default: 0] }.prefix(30)) { track in
                                HStack { Text(track.title); Spacer(); Text("\(p.playCounts[track.id, default: 0]) plays").foregroundStyle(.secondary) }
                            }
                        }
                    } else {
                        Section("Backup and Restore") {
                            Button("Create backup in Files") {
                                do { let url = try p.exportLibraryBackup(); message = "Backup created: \(url.lastPathComponent). Copy this folder outside the app using Files." }
                                catch { message = error.localizedDescription }
                            }
                            Button("Restore from MusixBackup folder") {
                                do { try p.restoreLibraryBackup(); message = "Library restored successfully." }
                                catch { message = error.localizedDescription }
                            }
                            Text("IMPORTANT: Copy the entire MusixBackup folder to iCloud Drive, a computer, or external storage BEFORE deleting Musix. Deleting the app also deletes backups kept inside its On My iPhone folder. Backups now include custom artist/album covers and Musix settings. To restore, copy the folder back to On My iPhone > Musix first.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Duplicate Song Finder") {
                            Button("Scan for identical audio files") { duplicates = p.duplicateGroups() }
                            if duplicates.isEmpty { Text("No duplicates shown. Run a scan to check.").font(.caption) }
                            ForEach(Array(duplicates.enumerated()), id: \.offset) { _, group in
                                VStack(alignment: .leading) {
                                    Text("\(group.count) identical copies").font(.headline)
                                    ForEach(group) { track in Text(track.title).font(.caption) }
                                }
                            }
                            Text("Uses SHA-256 file comparison. Review duplicates before deleting songs in Library.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("V99 Playback Preferences") {
                            Toggle("Animated Album Artwork", isOn: Binding(get: { p.animatedArtwork }, set: { p.setAnimatedArtwork($0) }))
                            Toggle("Volume Leveling (conservative)", isOn: Binding(get: { p.volumeNormalization }, set: { p.setVolumeNormalization($0) }))
                            Text("Volume leveling currently reduces output gain to prevent loud tracks from clipping. It does not yet measure per-song loudness.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Now Playing Extras") {
                            Button("Open full-screen karaoke lyrics") { showKaraoke = true }
                            Button("Open live audio visualizer") { showVisualizer = true }
                            Toggle("Expanded mini player", isOn: Binding(get: { p.miniPlayerExpanded }, set: { p.setMiniExpanded($0) }))
                        }
                        if !message.isEmpty { Section("Result") { Text(message) } }
                    }
                }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("More")
            .fullScreenCover(isPresented: $showKaraoke) { MusixKaraokeView() }
            .sheet(isPresented: $showVisualizer) { MusixAudioVisualizer() }
        }
    }

    private func quickFeature(_ title: String, icon: String, section target: Int) -> some View {
        Button { section = target } label: {
            Label(title, systemImage: icon)
        }.buttonStyle(.bordered)
    }
}

private struct MusixPlaylistDetail: View {
    @EnvironmentObject var p: PlayerModel
    let playlistID: UUID
    @State private var showAdd = false
    @State private var renameText = ""
    @State private var renaming = false
    private var playlist: MusixPlaylist? { p.playlists.first { $0.id == playlistID } }
    var body: some View {
        List {
            if let playlist {
                ForEach(p.playlistTracks(playlist)) { track in
                    Button { p.play(track, queue: p.playlistTracks(playlist)) } label: {
                        HStack { Text(track.title); Spacer(); Image(systemName: "play.fill") }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { p.removeFromPlaylist(track, playlist: playlistID) } }
                }
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                List(p.tracks) { track in
                    Button { p.addToPlaylist(track, playlist: playlistID) } label: {
                        HStack { Text(track.title); Spacer(); Image(systemName: "plus.circle") }
                    }
                }
                .navigationTitle("Add Songs")
                .toolbar { Button("Done") { showAdd = false } }
            }
        }
    }
}


struct MusixKaraokeView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            SpotifyInspiredBackground(data: p.current?.artworkData)
            Color.black.opacity(0.16).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.title2.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    Artwork(data: p.current?.artworkData)
                        .frame(width: 66, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.current?.title ?? "No song selected")
                            .font(.headline).lineLimit(2)
                        Text(p.current?.artist.isEmpty == false ? (p.current?.artist ?? "") : "Unknown Artist")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        Text(p.current?.album.isEmpty == false ? (p.current?.album ?? "") : "Unknown Album")
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 18)
                .padding(.top, 14)

                ScrollViewReader { proxy in
                    ScrollView {
                        if p.current?.lyrics.isEmpty != false {
                            VStack(spacing: 12) {
                                Image(systemName: "music.mic").font(.system(size: 36))
                                Text("No synchronized lyrics yet")
                                    .font(.title3.weight(.semibold))
                                Text("Import an LRC file or search for synced lyrics from Now Playing.")
                                    .font(.subheadline).multilineTextAlignment(.center)
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                            .padding(.horizontal, 24)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 22) {
                                ForEach(Array((p.current?.lyrics ?? []).enumerated()), id: \.offset) { index, line in
                                    let lines = p.current?.lyrics ?? []
                                    let active = p.time >= line.time && (index + 1 >= lines.count || p.time < lines[index + 1].time)
                                    Button { p.seek(line.time) } label: {
                                        Text(line.text)
                                            .font(.system(size: active ? 31 : 25, weight: active ? .bold : .medium))
                                            .foregroundStyle(active ? Color.white : Color.white.opacity(0.48))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .multilineTextAlignment(.leading)
                                            .padding(.vertical, 3)
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 38)
                        }
                    }
                    .onChange(of: Int(p.time)) { _ in
                        let lines = p.current?.lyrics ?? []
                        if let i = lines.indices.last(where: { lines[$0].time <= p.time }) {
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(i, anchor: .center) }
                        }
                    }
                }

                HStack(spacing: 48) {
                    Button { p.previous() } label: { Image(systemName: "backward.end.fill") }
                    Button { p.toggle() } label: {
                        Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    Button { p.next() } label: { Image(systemName: "forward.end.fill") }
                }
                .font(.title2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        // A downward swipe starting in the header dismisses karaoke.
        // Restricting the start area preserves scrolling and lyric-tap seeking.
        .simultaneousGesture(
            DragGesture(minimumDistance: 35)
                .onEnded { gesture in
                    if gesture.startLocation.y < 150 &&
                        gesture.translation.height > 85 &&
                        abs(gesture.translation.width) < gesture.translation.height {
                        dismiss()
                    }
                }
        )
    }
}

private struct MusixAudioVisualizer: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("musixCircularVisualizer") private var circular = false
    private let spectrum = LinearGradient(colors: [.blue, .purple, .pink], startPoint: .bottom, endPoint: .top)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Visualizer Style", selection: $circular) {
                    Text("Spectrum").tag(false)
                    Text("Circular").tag(true)
                }.pickerStyle(.segmented)
                Text(p.current?.title ?? "No song playing")
                    .font(.headline).lineLimit(2)
                if circular {
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, proxy.size.height)
                        ZStack {
                            Circle().fill(.ultraThinMaterial).frame(width: side * 0.48, height: side * 0.48)
                            if let data = p.current?.artworkData, let picture = UIImage(data: data) {
                                Image(uiImage: picture).resizable().scaledToFill()
                                    .frame(width: side * 0.45, height: side * 0.45)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "music.note").font(.system(size: 50)).foregroundStyle(.secondary)
                            }
                            ForEach(0..<20, id: \.self) { index in
                                Capsule().fill(spectrum)
                                    .frame(width: 8, height: 14 + CGFloat(p.audioLevels.indices.contains(index) ? p.audioLevels[index] : 0) * side * 0.20)
                                    .offset(y: -side * 0.34)
                                    .rotationEffect(.degrees(Double(index) * 18))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.linear(duration: 0.10), value: p.audioLevels)
                    }.frame(height: 300)
                } else {
                    GeometryReader { proxy in
                        HStack(alignment: .center, spacing: 4) {
                            ForEach(0..<20, id: \.self) { index in
                                Capsule().fill(spectrum)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: max(5, proxy.size.height * (p.audioLevels.indices.contains(index) ? p.audioLevels[index] : 0.025)))
                            }
                        }.frame(maxHeight: .infinity)
                        .animation(.linear(duration: 0.10), value: p.audioLevels)
                    }.frame(height: 190)
                }
                Text("Live frequency spectrum from the audio output")
                    .font(.caption).foregroundStyle(.secondary)
                Button(p.isPlaying ? "Pause" : "Play") { p.toggle() }
                    .buttonStyle(.borderedProminent)
                Spacer(minLength: 0)
            }.padding(24)
            .navigationTitle("Audio Visualizer")
            .onAppear { p.visualizerVisible = true }
            .onDisappear { p.visualizerVisible = false }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}


private struct MusixSmartPlaylistDetail: View {
    @EnvironmentObject private var p: PlayerModel
    let collection: PlayerModel.SmartCollection
    var body: some View {
        List {
            let songs = p.smartTracks(collection)
            if songs.isEmpty {
                Text("No songs in this smart playlist yet.").foregroundStyle(.secondary)
            } else {
                Button("Play All") { if let first = songs.first { p.play(first, queue: songs) } }
                ForEach(songs) { song in
                    Button {
                        p.play(song, queue: songs)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(song.title).foregroundStyle(.primary)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Play Next") { p.enqueue(song, next: true) }
                        Button("Add to Queue") { p.enqueue(song, next: false) }
                    }
                }
            }
        }
        .navigationTitle(collection.rawValue)
    }
}
