import SwiftUI

struct MusixExtrasView: View {
    @EnvironmentObject var p: PlayerModel
    @State private var name = ""
    @State private var selectedPlaylist: UUID?
    @State private var section = 0
    @State private var message = ""
    @State private var duplicates: [[Track]] = []
    @State private var showKaraoke = false
    @State private var showVisualizer = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $section) {
                    Text("Playlists").tag(0)
                    Text("Up Next").tag(1)
                    Text("Statistics").tag(2)
                    Text("Tools").tag(3)
                }.pickerStyle(.segmented).padding()
                List {
                    if section == 0 {
                        Section("Create playlist") {
                            HStack {
                                TextField("Playlist name", text: $name)
                                Button("Add") { p.createPlaylist(name); name = "" }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        ForEach(p.playlists) { playlist in
                            NavigationLink {
                                MusixPlaylistDetail(playlistID: playlist.id)
                            } label: {
                                Label(playlist.name, systemImage: "music.note.list")
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
                            Text("Total plays: \(p.playCounts.values.reduce(0, +))")
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
                            Text("To restore, place the complete MusixBackup folder in Files > On My iPhone > Musix first. Restoring does not delete other files.").font(.caption).foregroundStyle(.secondary)
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
                        Section("Now Playing Extras") {
                            Button("Open full-screen karaoke lyrics") { showKaraoke = true }
                            Button("Open live audio visualizer") { showVisualizer = true }
                            Toggle("Expanded mini player", isOn: Binding(get: { p.miniPlayerExpanded }, set: { p.setMiniExpanded($0) }))
                        }
                        if !message.isEmpty { Section("Result") { Text(message) } }
                    }
                }.listStyle(.insetGrouped)
            }
            .navigationTitle("My Music")
            .fullScreenCover(isPresented: $showKaraoke) { MusixKaraokeView() }
            .sheet(isPresented: $showVisualizer) { MusixAudioVisualizer() }
        }
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


private struct MusixKaraokeView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title2) }
                    Spacer()
                    Text(p.current?.title ?? "Lyrics").lineLimit(1)
                    Spacer()
                }.foregroundStyle(.white).padding()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(Array((p.current?.lyrics ?? []).enumerated()), id: \.offset) { index, line in
                                let active = p.time >= line.time && (index + 1 >= (p.current?.lyrics.count ?? 0) || p.time < (p.current?.lyrics[index + 1].time ?? .infinity))
                                Button { p.seek(line.time) } label: {
                                    Text(line.text).font(.system(size: active ? 31 : 26, weight: active ? .bold : .medium))
                                        .foregroundStyle(active ? Color.white : Color.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.id(index)
                            }
                        }.padding(24)
                    }
                    .onChange(of: Int(p.time)) { _ in
                        let lines = p.current?.lyrics ?? []
                        if let i = lines.indices.last(where: { lines[$0].time <= p.time }) {
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(i, anchor: .center) }
                        }
                    }
                }
                HStack {
                    Button { p.previous() } label: { Image(systemName: "backward.end.fill") }
                    Spacer()
                    Button { p.toggle() } label: { Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 56)) }
                    Spacer()
                    Button { p.next() } label: { Image(systemName: "forward.end.fill") }
                }.font(.title2).foregroundStyle(.white).padding(.horizontal, 45).padding(.bottom, 20)
            }
        }
    }
}


private struct MusixAudioVisualizer: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text(p.current?.title ?? "No song playing").font(.headline).lineLimit(2)
                GeometryReader { proxy in
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(p.audioLevels.indices, id: \.self) { i in
                            Capsule().fill(LinearGradient(colors: [.blue, .purple, .pink], startPoint: .bottom, endPoint: .top))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(5, proxy.size.height * p.audioLevels[i]))
                        }
                    }.frame(maxHeight: .infinity)
                }.frame(height: 180)
                Text("Live waveform energy from the playing audio").font(.caption).foregroundStyle(.secondary)
                Button(p.isPlaying ? "Pause" : "Play") { p.toggle() }.buttonStyle(.borderedProminent)
            }.padding(24)
            .navigationTitle("Audio Visualizer")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
