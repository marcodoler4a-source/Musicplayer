import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

struct ContentView: View {
    @EnvironmentObject var p: PlayerModel
    @State private var importing = false
    @State private var showPlayer = false
    @State private var showSleepTimer = false
    @State private var showQueue = false
    @State private var showLibraryActions = false
    @State private var showLibrarySortActions = false
    @State private var showLibraryFilterActions = false
    @State private var showSearch = false
    @State private var showLibrarySearch = false
    @State private var musicInfoTarget: Track?
    @State private var tagEditTarget: Track?
    @State private var tab = 0
    @State private var librarySection = "Songs"
    @State private var selectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmDeleteSelected = false
    @State private var showAlphabetIndex = false
    @State private var alphabetHideWorkItem: DispatchWorkItem?
    @State private var lastLibraryScrollOffset: CGFloat = 0
    @State private var currentScrollLetter = "A"
    @State private var libraryFilter = "All"
    @AppStorage("musixV102ShowContinue") private var showContinue = true
    @AppStorage("musixV102ShowOverview") private var showOverview = true
    @AppStorage("musixV102ArtistSort") private var artistSort = "Name"
    @AppStorage("musixV102PinnedArtists") private var pinnedArtistsJSON = "[]"
    @AppStorage("musixV102PinnedAlbums") private var pinnedAlbumsJSON = "[]"
    @State private var searchGenre = "All Genres"
    @State private var searchFavorites = false
    @State private var showMissingArtwork = false
    @State private var showStorageOverview = false
    @StateObject private var artistCovers = MusixArtistCoverStore.shared
    @State private var editingArtist: MusixArtistSelection?
    @State private var editingAlbum: MusixArtistSelection?
    @StateObject private var albumCovers = MusixAlbumCoverStore.shared
    @AppStorage("libraryGridMode") private var gridMode = false
    @AppStorage("musixCollectionGrid") private var collectionGrid = true
    @AppStorage("musixAlwaysShowAlphabet") private var alwaysShowAlphabet = true

    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("showArtwork") private var showArtwork = true
    @AppStorage("showMiniPlayer") private var showMiniPlayer = true
    @AppStorage("librarySort") private var librarySort = LibrarySort.title.rawValue
    @AppStorage("accentChoice") private var accentChoice = "Blue"

    private var accent: Color {
        switch accentChoice {
        case "Purple": return .purple
        case "Green": return .green
        case "Pink": return .pink
        default: return .blue
        }
    }

    private var sortedTracks: [Track] {
        switch librarySort {
        case LibrarySort.artist.rawValue:
            return p.tracks.sorted {
                $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
            }
        case LibrarySort.album.rawValue:
            return p.tracks.sorted {
                $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
            }
        case LibrarySort.recentlyAdded.rawValue:
            return Array(p.tracks.reversed())
        default:
            return p.tracks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    private var libraryVisibleTracks: [Track] {
        libraryFilter == "Favorites" ? sortedTracks.filter { p.isFavorite($0) } : sortedTracks
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                library
                    .tag(0)
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                favorites
                    .tag(1)
                    .tabItem { Label("Favorites", systemImage: "heart.fill") }

                recent
                    .tag(2)
                    .tabItem { Label("Recent", systemImage: "clock.fill") }

                albumsTab
                    .tag(3)
                    .tabItem { Label("Albums", systemImage: "square.stack.fill") }

                MusixExtrasView()
                    .tag(5)
                    .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
            }
            .tint(accent)

            if p.current != nil && showMiniPlayer && tab != 5 {
                MiniPlayer()
                    .onTapGesture { showPlayer = true }
                    .padding(.bottom, 49)
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingView().environmentObject(p)
        }
        .confirmationDialog("Sleep Timer", isPresented: $showSleepTimer, titleVisibility: .visible) {
            ForEach([0, 5, 10, 15, 20, 30, 45, 60, 90, 120], id: \.self) { minutes in
                Button((p.sleepMinutes == minutes ? "✓ " : "") + (minutes == 0 ? "Off" : "\(minutes) minutes")) {
                    p.setSleep(minutes)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(p.sleepMinutes > 0 ? "Currently set to \(p.sleepMinutes) minutes" : "Choose when playback should stop")
        }
        .sheet(isPresented: $showQueue) { MusixQueueSheet().environmentObject(p) }
        .sheet(item: $tagEditTarget) { song in
            EditAudioTagView(track: song).environmentObject(p)
        }
        .sheet(isPresented: $showSearch) {
            MusicInfoSearchView(target: musicInfoTarget).environmentObject(p)
        }
        .sheet(isPresented: $showLibrarySearch) {
            LibraryMusicSearchView(showPlayer: $showPlayer).environmentObject(p)
        }
        .sheet(isPresented: $importing) {
            NativeDocumentImporter { urls in
                importing = false
                guard !urls.isEmpty else {
                    p.userError = "No file was selected."
                    return
                }
                p.add(urls: urls)
            } onCancel: {
                importing = false
            } onError: { message in
                importing = false
                p.userError = "Could not open the selected file: \(message)"
            }
            .ignoresSafeArea()
        }
        .alert("Musix", isPresented: Binding(
            get: { p.userError != nil },
            set: { if !$0 { p.userError = nil } }
        )) {
            Button("OK", role: .cancel) { p.userError = nil }
        } message: {
            Text(p.userError ?? "")
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        LinearGradient(
            colors: [.black, Color(red: 0.03, green: 0.08, blue: 0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var library: some View {
        NavigationStack {
            ZStack {
                background
                VStack(spacing: 12) {
                    header("Library", subtitle: "Your music, beautifully local.")
                    Picker("Library View", selection: $librarySection) {
                        Text("Songs").tag("Songs")
                        Text("Artists").tag("Artists")
                        Text("Albums").tag("Albums")
                        Text("History").tag("History")
                        Text("Genres").tag("Genres")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if selectMode {
                        HStack(spacing: 12) {
                            Text("\(selectedIDs.count) selected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(selectedIDs.count == libraryVisibleTracks.count && !libraryVisibleTracks.isEmpty ? "Clear All" : "Select All") {
                                if selectedIDs.count == libraryVisibleTracks.count && !libraryVisibleTracks.isEmpty {
                                    selectedIDs.removeAll()
                                } else {
                                    selectedIDs = Set(libraryVisibleTracks.map(\.id))
                                }
                            }
                            .font(.subheadline.weight(.semibold))

                            Button(role: .destructive) {
                                confirmDeleteSelected = true
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                                    .font(.subheadline.weight(.bold))
                            }
                            .disabled(selectedIDs.isEmpty)

                            Button("Done") {
                                selectMode = false
                                selectedIDs.removeAll()
                            }
                            .font(.subheadline.weight(.bold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                    }

                    ScrollViewReader { proxy in
                    ScrollView {
                      VStack(spacing: 16) {
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: LibraryScrollOffsetKey.self,
                                            value: geo.frame(in: .named("libraryScroll")).minY)
                        }
                        .frame(height: 0)
                        if librarySection == "Songs" && showContinue && !p.historyTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Label("Continue Listening", systemImage: "play.circle.fill").font(.headline)
                                    Spacer()
                                    Button("Hide") { showContinue = false }.font(.caption)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(p.historyTracks.prefix(8))) { song in
                                            Button { p.play(song); showPlayer = true } label: {
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Artwork(data: song.artworkData).frame(width: 94, height: 94)
                                                    Text(song.title).font(.caption).lineLimit(1).frame(width: 94, alignment: .leading)
                                                }
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }.padding(.horizontal)
                        }
                        if librarySection == "Songs" && showOverview {
                            HStack {
                                Label("\(p.tracks.count) songs", systemImage: "music.note")
                                Spacer()
                                Button("Storage & Cleanup") { showStorageOverview = true }.font(.caption)
                            }.font(.subheadline).padding(12)
                             .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                             .padding(.horizontal)
                        }
                        if p.tracks.isEmpty {
                            empty(
                                "music.note.list",
                                "Import your music",
                                "Add MP3, M4A, AAC, WAV and other iOS-supported audio files."
                            )
                        } else if librarySection == "Artists" {
                            artistLibrary
                        } else if librarySection == "Albums" {
                            albumLibrary
                        } else if librarySection == "History" {
                            historyLibrary
                        } else if librarySection == "Genres" {
                            genreLibrary
                        } else {
                            if gridMode {
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ], spacing: 16) {
                                    ForEach(libraryVisibleTracks) { track in
                                        trackGridCard(track, queue: libraryVisibleTracks)
                                    }
                                }
                                .padding(.horizontal)
                            } else {
                                LazyVStack(spacing: compactRows ? 5 : 10) {
                                    ForEach(libraryVisibleTracks) { track in
                                        trackRow(track, queue: libraryVisibleTracks)
                                            .background(GeometryReader { rowGeo in
                                                Color.clear.preference(key: MusixVisibleLettersKey.self,
                                                    value: [track.id: MusixLetterPosition(y: rowGeo.frame(in: .named("libraryScroll")).minY, letter: String(track.title.prefix(1)).uppercased())])
                                            })
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    }
                    .coordinateSpace(name: "libraryScroll")
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { _ in
                                guard librarySection == "Songs", !gridMode, !libraryVisibleTracks.isEmpty else { return }
                                showAlphabetIndex = true
                                alphabetHideWorkItem?.cancel()
                            }
                            .onEnded { _ in
                                guard showAlphabetIndex else { return }
                                alphabetHideWorkItem?.cancel()
                                let work = DispatchWorkItem { showAlphabetIndex = false }
                                alphabetHideWorkItem = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
                            }
                    )
                    .onPreferenceChange(MusixVisibleLettersKey.self) { positions in
                        guard librarySection == "Songs", !gridMode, !positions.isEmpty else { return }
                        var nearestLetter: String? = nil
                        var nearestDistance: CGFloat = .greatestFiniteMagnitude
                        for position in positions.values {
                            let distance: CGFloat = abs(position.y - CGFloat(12))
                            if distance < nearestDistance {
                                nearestDistance = distance
                                nearestLetter = position.letter
                            }
                        }
                        if let letter = nearestLetter {
                            let isLetter = letter.count == 1 && letter.first.map { $0 >= "A" && $0 <= "Z" } == true
                            currentScrollLetter = isLetter ? letter : "#"
                        }
                    }
                    .onPreferenceChange(LibraryScrollOffsetKey.self) { offset in
                        guard librarySection == "Songs", !gridMode, !libraryVisibleTracks.isEmpty else { return }
                        let moved = abs(offset - lastLibraryScrollOffset) > 0.5
                        lastLibraryScrollOffset = offset
                        guard moved else { return }
                        showAlphabetIndex = true
                        alphabetHideWorkItem?.cancel()
                        let work = DispatchWorkItem { showAlphabetIndex = false }
                        alphabetHideWorkItem = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
                    }
                    .overlay(alignment: .trailing) {
                        if (showAlphabetIndex || alwaysShowAlphabet) && librarySection == "Songs" && !gridMode {
                            alphabetIndex(proxy: proxy)
                                .transition(.opacity)
                                .padding(.trailing, 7)
                                .zIndex(100)
                        }
                    }
                    .animation(.easeOut(duration: 0.18), value: showAlphabetIndex)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                  }
                }
            }
            .sheet(isPresented: $showStorageOverview) {
                MusixLibraryOverview(tracks: p.tracks, onFindMissing: {
                    showStorageOverview = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showMissingArtwork = true }
                })
            }
            .sheet(isPresented: $showMissingArtwork) {
                NavigationStack {
                    List(p.tracks.filter { $0.artworkData == nil }) { song in
                        HStack { Image(systemName: "music.note"); VStack(alignment: .leading) {
                            Text(song.title); Text(song.artist).font(.caption).foregroundStyle(.secondary)
                        }}
                    }
                    .navigationTitle("Missing Artwork")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showMissingArtwork = false } } }
                }.preferredColorScheme(.dark)
            }
            .alert("Delete Selected Songs?", isPresented: $confirmDeleteSelected) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(selectedIDs.count)", role: .destructive) {
                    let ids = selectedIDs
                    let tracksToDelete = p.tracks.filter { ids.contains($0.id) }
                    for track in tracksToDelete { p.remove(track) }
                    selectedIDs.removeAll()
                    selectMode = false
                }
            } message: {
                Text("This will remove the selected songs from your Musix library.")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var genreLibrary: some View {
        let groups = Dictionary(grouping: p.tracks) { $0.genre.isEmpty ? "Unknown Genre" : $0.genre }
        return LazyVStack(spacing: 12) {
            ForEach(groups.keys.sorted(), id: \.self) { genre in
                let songs = groups[genre] ?? []
                NavigationLink {
                    List(songs) { song in
                        Button { p.play(song, queue: songs); showPlayer = true } label: {
                            HStack { Artwork(data: song.artworkData).frame(width: 48, height: 48)
                                VStack(alignment: .leading) { Text(song.title); Text(song.artist).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.buttonStyle(.plain)
                    }.navigationTitle(genre)
                } label: {
                    HStack { Image(systemName: "square.stack.fill").foregroundStyle(accent)
                        Text(genre).font(.headline); Spacer(); Text("\(songs.count) songs").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                    }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal)
    }

    private var historyLibrary: some View {
        LazyVStack(spacing: compactRows ? 5 : 10) {
            HStack {
                Label("Recently Played", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if !p.playbackHistory.isEmpty {
                    Button("Clear History", role: .destructive) { p.clearPlaybackHistory() }
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            if p.historyTracks.isEmpty {
                empty("clock.arrow.circlepath", "No listening history yet", "Songs you play will appear here, newest first.")
            } else {
                ForEach(Array(p.historyTracks.enumerated()), id: \.offset) { _, track in
                    trackRow(track, queue: p.historyTracks)
                }
                .padding(.horizontal)
            }
        }
    }

    private func pinned(_ json: String) -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? [])
    }
    private func togglePin(_ name: String, artist: Bool) {
        var values = pinned(artist ? pinnedArtistsJSON : pinnedAlbumsJSON)
        if values.contains(name) { values.remove(name) } else { values.insert(name) }
        let encoded = (try? JSONEncoder().encode(values.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        if artist { pinnedArtistsJSON = encoded } else { pinnedAlbumsJSON = encoded }
    }

    private var artistLibrary: some View {
        let groups = Dictionary(grouping: sortedTracks) { track in
            track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Artist" : track.artist
        }
        return LazyVGrid(columns: collectionGrid ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.flexible())], spacing: 12) {
            ForEach(groups.keys.sorted { a, b in
                let pins = pinned(pinnedArtistsJSON)
                if pins.contains(a) != pins.contains(b) { return pins.contains(a) }
                if artistSort == "Song Count" && groups[a, default: []].count != groups[b, default: []].count {
                    return groups[a, default: []].count > groups[b, default: []].count
                }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }, id: \.self) { artist in
                let songs = groups[artist] ?? []
                NavigationLink {
                    MusixArtistCollectionView(artist: artist, songs: songs)
                        .environmentObject(p)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        if !collectionGrid { EmptyView() }
                        if let art = artistCovers.cover(for: artist) ?? songs.first(where: { $0.artworkData != nil })?.artworkData {
                            Artwork(data: art).frame(maxWidth: .infinity).frame(height: collectionGrid ? 134 : 100).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 54)).foregroundStyle(.cyan)
                                .frame(maxWidth: .infinity).frame(height: collectionGrid ? 134 : 100)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(artist).font(.headline).foregroundStyle(.white).lineLimit(2).truncationMode(.tail).frame(height: 43, alignment: .topLeading)
                            Text("\(songs.count) songs").font(.subheadline).foregroundStyle(.secondary)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: collectionGrid ? 230 : 190, alignment: .top)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { togglePin(artist, artist: true) } label: {
                        Label(pinned(pinnedArtistsJSON).contains(artist) ? "Unpin Artist" : "Pin Artist", systemImage: "pin")
                    }
                    Button { editingArtist = MusixArtistSelection(name: artist) } label: { Label("Edit Artist Cover", systemImage: "photo") }
                    Button { MusixArtistCoverSearch.open(artist) } label: { Label("Search Artist Photo", systemImage: "magnifyingglass") }
                    if artistCovers.hasCover(for: artist) {
                        Button(role: .destructive) { artistCovers.remove(artist: artist) } label: { Label("Reset Cover", systemImage: "arrow.counterclockwise") }
                    }
                }
            }
        }
        .padding(.horizontal)
        .sheet(item: $editingArtist) { artist in
            MusixArtistCoverEditor(artist: artist.name)
        }
    }

    private var albumLibrary: some View {
        let groups = Dictionary(grouping: sortedTracks) { track in
            track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Album" : track.album
        }
        return LazyVGrid(columns: collectionGrid ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.flexible())], spacing: 12) {
            ForEach(groups.keys.sorted { a, b in
                let pins = pinned(pinnedAlbumsJSON)
                if pins.contains(a) != pins.contains(b) { return pins.contains(a) }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }, id: \.self) { album in
                let songs = groups[album] ?? []
                NavigationLink {
                    MusixAlbumCollectionView(album: album, songs: songs).environmentObject(p)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        if !collectionGrid { EmptyView() }
                        if let art = albumCovers.cover(for: album) ?? songs.first(where: { $0.artworkData != nil })?.artworkData {
                            Artwork(data: art).frame(maxWidth: .infinity).frame(height: collectionGrid ? 134 : 100).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 48)).foregroundStyle(.cyan)
                                .frame(maxWidth: .infinity).frame(height: collectionGrid ? 134 : 100)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(album).font(.headline).foregroundStyle(.white).lineLimit(2).truncationMode(.tail).frame(height: 43, alignment: .topLeading)
                            Text(songs.first?.artist ?? "Unknown Artist").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(songs.count) songs").font(.caption).foregroundStyle(.secondary)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: collectionGrid ? 230 : 190, alignment: .top)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { togglePin(album, artist: false) } label: {
                        Label(pinned(pinnedAlbumsJSON).contains(album) ? "Unpin Album" : "Pin Album", systemImage: "pin")
                    }
                    Button { editingAlbum = MusixArtistSelection(name: album) } label: { Label("Add / Replace Album Image", systemImage: "photo") }
                    Button { MusixAlbumCoverSearch.open(album) } label: { Label("Search Album Image", systemImage: "magnifyingglass") }
                    if albumCovers.hasCover(for: album) {
                        Button(role: .destructive) { albumCovers.remove(artist: album) } label: { Label("Reset Album Image", systemImage: "arrow.counterclockwise") }
                    }
                }
            }
        }
        .padding(.horizontal)
        .sheet(item: $editingAlbum) { album in
            MusixAlbumCoverEditor(album: album.name)
        }
    }

    private var favorites: some View {
        NavigationStack {
            ZStack {
                background
                VStack(spacing: 12) {
                    header("Favorites", subtitle: "The songs you love.")
                    ScrollView {
                        VStack(spacing: 16) {
                            let favs = sortedTracks.filter { p.isFavorite($0) }
                            if favs.isEmpty {
                                empty("heart", "No favorites yet", "Tap the heart beside a song to add it here.")
                            } else {
                                LazyVStack(spacing: compactRows ? 5 : 10) {
                                    ForEach(favs) { track in trackRow(track, queue: favs) }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var recent: some View {
        NavigationStack {
            ZStack {
                background
                VStack(spacing: 12) {
                    header("Recent", subtitle: "Recently added to your library.")
                    ScrollView {
                        VStack(spacing: 16) {
                            let recentTracks = Array(p.tracks.reversed())
                            if recentTracks.isEmpty {
                                empty("clock", "No recent music", "Imported songs will appear here.")
                            } else {
                                LazyVStack(spacing: compactRows ? 5 : 10) {
                                    ForEach(recentTracks) { track in trackRow(track, queue: recentTracks) }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var albumsTab: some View {
        NavigationStack {
            ZStack {
                background
                VStack(spacing: 12) {
                    header("Albums", subtitle: "Browse your music by album.")
                    ScrollView {
                        VStack(spacing: 16) {
                            if p.tracks.isEmpty {
                                empty("square.stack", "No albums yet", "Import music to build your album library.")
                            } else {
                                albumLibrary
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func header(_ title: String, subtitle: String, count: Int? = nil) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.bold())
                    if let count = count {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showLibrarySearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Button { importing = true } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            LibraryStableOptionsMenu(
                selectMode: $selectMode,
                selectedIDs: $selectedIDs,
                gridMode: $gridMode,
                librarySort: $librarySort,
                libraryFilter: $libraryFilter,
                tab: $tab,
                showLibrarySearch: $showLibrarySearch,
                showSleepTimer: $showSleepTimer,
                showQueue: $showQueue
            )
        }
        .padding(.horizontal)
    }

    private func empty(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 70)
    }

    private var libraryAlphabet: [String] {
        let letters = libraryVisibleTracks.compactMap { track -> String? in
            guard let first = track.title.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
            let value = String(first).uppercased()
            return value.range(of: "^[A-Z]$", options: .regularExpression) != nil ? value : "#"
        }
        let unique = Set(letters)
        return (["#"] + (65...90).compactMap { UnicodeScalar($0).map { String(Character($0)) } })
            .filter { unique.contains($0) }
    }

    private func firstTrack(for letter: String) -> Track? {
        libraryVisibleTracks.first { track in
            guard let first = track.title.trimmingCharacters(in: .whitespacesAndNewlines).first else { return false }
            let value = String(first).uppercased()
            if letter == "#" { return value.range(of: "^[A-Z]$", options: .regularExpression) == nil }
            return value == letter
        }
    }

    private func alphabetIndex(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ForEach(libraryAlphabet, id: \.self) { letter in
                Button {
                    if let track = firstTrack(for: letter) {
                        withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(track.id, anchor: .top) }
                    }
                    showAlphabetIndex = true
                    alphabetHideWorkItem?.cancel()
                    let work = DispatchWorkItem { showAlphabetIndex = false }
                    alphabetHideWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
                } label: {
                    Text(letter)
                        .font(.system(size: letter == currentScrollLetter ? 13 : 11,
                                      weight: letter == currentScrollLetter ? .black : .bold,
                                      design: .rounded))
                        .foregroundStyle(letter == currentScrollLetter ? Color.white : accent)
                        .frame(width: 26, height: 17)
                        .background {
                            if letter == currentScrollLetter {
                                Capsule().fill(accent)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(accent)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 4)
    }

    private func trackGridCard(_ t: Track, queue: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if selectMode {
                    if selectedIDs.contains(t.id) { selectedIDs.remove(t.id) } else { selectedIDs.insert(t.id) }
                } else {
                    p.play(t, queue: queue)
                    showPlayer = true
                }
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    ZStack(alignment: .topTrailing) {
                        Artwork(data: t.artworkData)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        if selectMode {
                            Image(systemName: selectedIDs.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(selectedIDs.contains(t.id) ? accent : .white)
                                .padding(8)
                                .background(.black.opacity(0.35), in: Circle())
                                .padding(6)
                        }
                    }
                    Text(t.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(t.artist.isEmpty ? "Unknown Artist" : t.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            if !selectMode {
            HStack {
                Button { p.toggleFavorite(t) } label: {
                    Image(systemName: p.isFavorite(t) ? "heart.fill" : "heart")
                        .foregroundStyle(p.isFavorite(t) ? accent : .secondary)
                }
                Spacer()
                MusixStableSongOptionsMenu(
                    onSearch: { musicInfoTarget = t; showSearch = true },
                onEdit: { tagEditTarget = t },
                    onPlayNext: { p.enqueue(t, next: true) },
                    onAddToQueue: { p.enqueue(t, next: false) },
                    onRemove: { p.remove(t) }
                )
            }
            .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .contextMenu {
            Button { p.toggleFavorite(t) } label: {
                Label(p.isFavorite(t) ? "Remove from Favorites" : "Add to Favorites", systemImage: p.isFavorite(t) ? "heart.slash" : "heart")
            }
            Button { musicInfoTarget = t; showSearch = true } label: {
                Label("Search Music Info", systemImage: "magnifyingglass")
            }
            Button { p.enqueue(t, next: true) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                    Button { p.enqueue(t, next: false) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
                    Button(role: .destructive) { p.remove(t) } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }

    private func trackRow(_ t: Track, queue: [Track]) -> some View {
        HStack(spacing: 12) {
            if selectMode {
                Button {
                    if selectedIDs.contains(t.id) { selectedIDs.remove(t.id) } else { selectedIDs.insert(t.id) }
                } label: {
                    Image(systemName: selectedIDs.contains(t.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                }
            }
            Button {
                p.play(t, queue: queue)
                showPlayer = true
            } label: {
                HStack(spacing: 12) {
                    if showArtwork {
                        Artwork(data: t.artworkData)
                            .frame(
                                width: compactRows ? 46 : 58,
                                height: compactRows ? 46 : 58
                            )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(.headline).lineLimit(1)
                        Text(t.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !compactRows && !t.album.isEmpty {
                            Text(t.album)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if p.current?.id == t.id {
                        MusixPlayingBars(active: p.isPlaying)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                p.toggleFavorite(t)
            } label: {
                Image(systemName: p.isFavorite(t) ? "heart.fill" : "heart")
                    .foregroundStyle(p.isFavorite(t) ? accent : .secondary)
                    .padding(8)
            }

            MusixStableSongOptionsMenu(
                onSearch: { musicInfoTarget = t; showSearch = true },
                onEdit: { tagEditTarget = t },
                onPlayNext: { p.enqueue(t, next: true) },
                onAddToQueue: { p.enqueue(t, next: false) },
                onRemove: { p.remove(t) }
            )
        }
        .padding(compactRows ? 6 : 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                p.toggleFavorite(t)
            } label: {
                Label(p.isFavorite(t) ? "Remove from Favorites" : "Add to Favorites", systemImage: p.isFavorite(t) ? "heart.slash" : "heart")
            }
            Button {
                musicInfoTarget = t
                showSearch = true
            } label: {
                Label("Search Music Info", systemImage: "magnifyingglass")
            }
            Button { p.enqueue(t, next: true) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { p.enqueue(t, next: false) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
            Button(role: .destructive) {
                p.remove(t)
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }
}

struct LibraryMusicSearchView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @Binding var showPlayer: Bool
    @State private var query = ""
    @State private var genreFilter = "All Genres"
    @State private var favoritesOnly = false

    private var results: [Track] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.tracks.filter { track in
            (q.isEmpty || track.title.localizedCaseInsensitiveContains(q) ||
             track.artist.localizedCaseInsensitiveContains(q) ||
             track.album.localizedCaseInsensitiveContains(q) ||
             track.genre.localizedCaseInsensitiveContains(q) ||
             track.releaseDate.localizedCaseInsensitiveContains(q) ||
             track.url.lastPathComponent.localizedCaseInsensitiveContains(q)) &&
            (genreFilter == "All Genres" || track.genre == genreFilter) &&
            (!favoritesOnly || p.isFavorite(track))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("Genre", selection: $genreFilter) {
                        Text("All Genres").tag("All Genres")
                        ForEach(Array(Set(p.tracks.map(\.genre).filter { !$0.isEmpty })).sorted(), id: \.self) { genre in
                            Text(genre).tag(genre)
                        }
                    }
                    Toggle("Favorites", isOn: $favoritesOnly).labelsHidden()
                    Image(systemName: "heart.fill").foregroundStyle(.secondary)
                }.padding(.horizontal)
                    List(results) { track in
                Button {
                    p.play(track, queue: results)
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { showPlayer = true }
                } label: {
                    HStack(spacing: 12) {
                        Artwork(data: track.artworkData).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.headline).lineLimit(1)
                            Text(track.artist.isEmpty ? track.url.lastPathComponent : track.artist)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your songs")
            .navigationTitle("Search Music")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct Artwork: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.blue.opacity(0.8), .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note").font(.largeTitle)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var p: PlayerModel

    var body: some View {
        HStack {
            Artwork(data: p.current?.artworkData)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(p.current?.title ?? "").bold().lineLimit(1)
                Text(p.current?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if p.miniPlayerExpanded {
                    GeometryReader { geometry in
                        Capsule().fill(.secondary.opacity(0.25))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.blue).frame(width: geometry.size.width * CGFloat(min(1, max(0, p.duration > 0 ? p.time / p.duration : 0))))
                            }
                    }.frame(height: 3).padding(.top, 3)
                }
            }

            Spacer()

            Button { p.toggle() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Button { p.next() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal)
    }
}


// MARK: - Native iOS document picker
// V52: UIKit's picker delegate receives the selected URLs directly.  We hand
// them to PlayerModel before dismissing the sheet so security-scoped provider
// access is still valid while the files are copied into Musix Documents.
private struct NativeDocumentImporter: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept every document at picker level. Some Files providers advertise .lrc
        // with an unexpected/dynamic UTI (often like subtitles), which caused iOS to
        // show the file but disable tapping it. Musix validates the extension itself
        // after selection, so .item is the reliable choice here.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void
        let onError: (String) -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void, onError: @escaping (String) -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else {
                onError("iOS returned no selected file URL.")
                return
            }
            // V53 uses asCopy=true. iOS first creates app-readable temporary copies,
            // so local Files and third-party File Provider URLs do not depend on
            // Musix retaining the provider's original security-scoped URL.
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

private struct MusixLetterPosition: Equatable {
    let y: CGFloat
    let letter: String
}

private struct MusixVisibleLettersKey: PreferenceKey {
    static var defaultValue: [UUID: MusixLetterPosition] = [:]
    static func reduce(value: inout [UUID: MusixLetterPosition], nextValue: () -> [UUID: MusixLetterPosition]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct LibraryScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// V88: Shared sleep timer and queue controls for Library and Now Playing.
struct MusixSleepTimerSheet: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    private let choices = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.cyan)
                Text("Sleep Timer").font(.title3.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
            }
            Text(p.sleepMinutes > 0 ? "Music will pause after \(p.sleepMinutes) minutes." : "Choose when Musix should stop playing.")
                .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(choices, id: \.self) { minutes in
                        Button {
                            p.setSleep(minutes)
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Text(minutes == 0 ? "Off" : "\(minutes) min")
                                if p.sleepMinutes == minutes { Image(systemName: "checkmark.circle.fill") }
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(p.sleepMinutes == minutes ? Color.cyan.opacity(0.22) : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(22)
        .preferredColorScheme(.dark)
        .background(Color.clear)
    }
}

struct MusixQueueSheet: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let current = p.current {
                    Section("Now Playing") {
                        HStack { Text(current.title); Spacer(); Text(current.artist).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                Section("Added to Queue") {
                    if p.upcomingTracks.isEmpty { Text("No songs added yet. Use Play Next or Add to Queue on any song.").foregroundStyle(.secondary) }
                    ForEach(Array(p.upcomingTracks.enumerated()), id: \.offset) { index, track in
                        HStack { Text(track.title).lineLimit(1); Spacer(); Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .onDelete { offsets in for index in offsets.sorted(by: >) { p.removeQueued(at: index) } }
                    .onMove { p.moveQueued(from: $0, to: $1) }
                }
                Section("Regular Playback Queue") {
                    ForEach(p.activeQueue()) { track in
                        HStack { Text(track.title).lineLimit(1); Spacer(); Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }
            .navigationTitle("Up Next")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct MusixArtistCollectionView: View {
    @EnvironmentObject var p: PlayerModel
    @State private var showPlayer = false
    @State private var editingCover = false
    @StateObject private var artistCovers = MusixArtistCoverStore.shared
    let artist: String
    let songs: [Track]
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Group {
                    if let art = artistCovers.cover(for: artist) ?? songs.first(where: { $0.artworkData != nil })?.artworkData {
                        Artwork(data: art).frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 76)).foregroundStyle(.cyan)
                    }
                    }
                    .frame(width: 96, height: 96)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button { editingCover = true } label: { Label("Add / Replace Artist Image", systemImage: "photo") }
                        Button { MusixArtistCoverSearch.open(artist) } label: { Label("Search Artist Image", systemImage: "magnifyingglass") }
                        if artistCovers.hasCover(for: artist) {
                            Button(role: .destructive) { artistCovers.remove(artist: artist) } label: { Label("Reset Artist Image", systemImage: "arrow.counterclockwise") }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(artist).font(.title2.bold())
                        Text("\(songs.count) songs").foregroundStyle(.secondary)
                        Button("Play All") { if let first = songs.first { p.play(first, queue: songs); showPlayer = true } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("Songs") {
                ForEach(songs) { track in
                    HStack {
                        Button {
                            p.play(track, queue: songs)
                            showPlayer = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).foregroundStyle(.primary)
                                if !track.album.isEmpty { Text(track.album).font(.caption).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Menu {
                            Button { p.enqueue(track, next: true) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            Button { p.enqueue(track, next: false) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
                        } label: { Image(systemName: "ellipsis").padding(8) }
                    }
                }
            }
        }
        .navigationTitle(artist)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editingCover = true } label: { Label("Edit Artist Cover", systemImage: "photo") }
                    Button { MusixArtistCoverSearch.open(artist) } label: { Label("Search Artist Photo", systemImage: "magnifyingglass") }
                    if artistCovers.hasCover(for: artist) {
                        Button(role: .destructive) { artistCovers.remove(artist: artist) } label: { Label("Reset Cover", systemImage: "arrow.counterclockwise") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editingCover) { MusixArtistCoverEditor(artist: artist) }
        .fullScreenCover(isPresented: $showPlayer) { NowPlayingView().environmentObject(p) }
    }
}

struct MusixAlbumCollectionView: View {
    @EnvironmentObject var p: PlayerModel
    @StateObject private var covers = MusixAlbumCoverStore.shared
    @State private var editingCover = false
    @State private var showPlayer = false
    let album: String
    let songs: [Track]

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Group {
                        if let art = covers.cover(for: album) ?? songs.first(where: { $0.artworkData != nil })?.artworkData {
                            Artwork(data: art).frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            Image(systemName: "square.stack.fill").font(.system(size: 70)).foregroundStyle(.cyan)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .contentShape(Rectangle())
                    .contextMenu { coverMenu }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album).font(.title2.bold())
                        Text(songs.first?.artist ?? "Unknown Artist").foregroundStyle(.secondary)
                        Text("\(songs.count) songs").font(.caption).foregroundStyle(.secondary)
                        Button("Play All") { if let first = songs.first { p.play(first, queue: songs); showPlayer = true } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("Songs") {
                ForEach(songs) { track in
                    HStack {
                        Button {
                            p.play(track, queue: songs)
                            showPlayer = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).foregroundStyle(.primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Menu {
                            Button { p.enqueue(track, next: true) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            Button { p.enqueue(track, next: false) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
                        } label: { Image(systemName: "ellipsis").padding(8) }
                    }
                }
            }
        }
        .navigationTitle(album)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { coverMenu } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editingCover) { MusixAlbumCoverEditor(album: album) }
        .fullScreenCover(isPresented: $showPlayer) { NowPlayingView().environmentObject(p) }
    }

    @ViewBuilder private var coverMenu: some View {
        Button { editingCover = true } label: { Label("Add / Replace Album Image", systemImage: "photo") }
        Button { MusixAlbumCoverSearch.open(album) } label: { Label("Search Album Image", systemImage: "magnifyingglass") }
        if covers.hasCover(for: album) {
            Button(role: .destructive) { covers.remove(artist: album) } label: { Label("Reset Album Image", systemImage: "arrow.counterclockwise") }
        }
    }
}


// A separate menu view deliberately does not observe PlayerModel. Playback progress
// publishes frequently, but must not rebuild an open UIKit-backed SwiftUI Menu.
private struct LibraryStableOptionsMenu: View {
    @AppStorage("musixCollectionGrid") private var collectionGrid = true
    @AppStorage("musixAlwaysShowAlphabet") private var alwaysShowAlphabet = true
    @Binding var selectMode: Bool
    @Binding var selectedIDs: Set<UUID>
    @Binding var gridMode: Bool
    @Binding var librarySort: String
    @Binding var libraryFilter: String
    @Binding var tab: Int
    @Binding var showLibrarySearch: Bool
    @Binding var showSleepTimer: Bool
    @Binding var showQueue: Bool

    var body: some View {
        Menu {
            Button(selectMode ? "Done Selecting" : "Select", systemImage: "checkmark.circle") {
                selectMode.toggle()
                if !selectMode { selectedIDs.removeAll() }
            }
            Button("Search Music Files", systemImage: "magnifyingglass") { showLibrarySearch = true }
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                ForEach(LibrarySort.allCases) { option in
                    Button {
                        librarySort = option.rawValue
                    } label: {
                        if librarySort == option.rawValue {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            }
            Menu("Filter", systemImage: "line.3.horizontal.decrease") {
                Button {
                    libraryFilter = "All"
                } label: {
                    Label("All songs", systemImage: libraryFilter == "All" ? "checkmark" : "music.note")
                }
                Button {
                    libraryFilter = "Favorites"
                } label: {
                    Label("Favorites", systemImage: libraryFilter == "Favorites" ? "checkmark" : "heart")
                }
            }
            Button(gridMode ? "List" : "Grid", systemImage: gridMode ? "list.bullet" : "square.grid.2x2") {
                gridMode.toggle()
            }
            Button(alwaysShowAlphabet ? "Hide A–Z Index" : "Always Show A–Z", systemImage: "textformat.abc") { alwaysShowAlphabet.toggle() }
            Divider()
            Button("Sleep Timer", systemImage: "moon") { showSleepTimer = true }
            Button("Up Next Queue", systemImage: "text.line.first.and.arrowtriangle.forward") { showQueue = true }
            Button("Settings", systemImage: "gearshape") {
                UserDefaults.standard.set(5, forKey: "musixMoreSection")
                tab = 5
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("Library options")
    }
}


// Keep the native song options menu separate from the playback-observing library.
// In particular, progress changes must not mutate the menu's label or contents.
private struct MusixStableSongOptionsMenu: View {
    let onSearch: () -> Void
    let onEdit: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button(action: onSearch) {
                Label("Search Music Info Online", systemImage: "magnifyingglass.circle")
            }
            Button(action: onEdit) {
                Label("Edit Audio Tags", systemImage: "pencil")
            }
            Button(action: onPlayNext) {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button(action: onAddToQueue) {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Library", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil }
        .accessibilityLabel("Song options")
    }
}

// V100: Low-cost indicator only instantiated for the active song.
private struct MusixPlayingBars: View {
    let active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.22, paused: !active)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(Color.cyan)
                        .frame(width: 3, height: active ? 5 + 13 * abs(sin(phase * 4 + Double(i) * 1.4)) : 5)
                }
            }.frame(width: 15, height: 20)
        }
        .accessibilityLabel(active ? "Now playing" : "Paused")
    }
}

private struct MusixLibraryOverview: View {
    let tracks: [Track]
    let onFindMissing: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Songs", value: "\(tracks.count)")
                LabeledContent("Artists", value: "\(Set(tracks.map(\.artist)).count)")
                LabeledContent("Albums", value: "\(Set(tracks.map(\.album)).count)")
                LabeledContent("Missing Artwork", value: "\(tracks.filter { $0.artworkData == nil }.count)")
                Button("Find Songs Missing Artwork", action: onFindMissing)
                Section { Text("Music is stored in the app's documents folder. Back up your library before uninstalling Musix.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Library Overview")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
