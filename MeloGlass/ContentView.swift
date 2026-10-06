import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @EnvironmentObject var p: PlayerModel
    @State private var importing = false
    @State private var showPlayer = false
    @State private var showSearch = false
    @State private var musicInfoTarget: Track?
    @State private var tab = 0
    @State private var librarySection = "Songs"
    @State private var selectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmDeleteSelected = false
    @State private var libraryFilter = "All"
    @AppStorage("libraryGridMode") private var gridMode = false

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

                AppearanceSettingsView()
                    .tag(4)
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
            .tint(accent)

            if p.current != nil && showMiniPlayer && tab != 4 {
                MiniPlayer()
                    .onTapGesture { showPlayer = true }
                    .padding(.bottom, 49)
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingView().environmentObject(p)
        }
        .sheet(isPresented: $showSearch) {
            MusicInfoSearchView(target: musicInfoTarget).environmentObject(p)
        }
        .fileImporter(
            isPresented: $importing,
            // Select the audio file and its matching .lrc file together.
            // Example: "My Song.mp3" + "My Song.lrc".
            allowedContentTypes: [.audio, .plainText],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                p.add(urls: urls)
            }
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
                    header("Library", subtitle: "Your music, beautifully local.", count: p.tracks.count)
                    Picker("Library View", selection: $librarySection) {
                        Text("Songs").tag("Songs")
                        Text("Artists").tag("Artists")
                        Text("Albums").tag("Albums")
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

                    ScrollView {
                      VStack(spacing: 16) {
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
                                    ForEach(libraryVisibleTracks) { track in trackRow(track, queue: libraryVisibleTracks) }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                  }
                }
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

    private var artistLibrary: some View {
        let groups = Dictionary(grouping: sortedTracks) { track in
            track.artist.isEmpty ? "Unknown Artist" : track.artist
        }
        return LazyVStack(spacing: 18) {
            ForEach(groups.keys.sorted(), id: \.self) { artist in
                VStack(alignment: .leading, spacing: 8) {
                    Text(artist).font(.title3.bold()).padding(.horizontal, 4)
                    ForEach(groups[artist] ?? []) { track in trackRow(track, queue: groups[artist] ?? []) }
                }
            }
        }
        .padding(.horizontal)
    }

    private var albumLibrary: some View {
        let groups = Dictionary(grouping: sortedTracks) { track in
            track.album.isEmpty ? "Unknown Album" : track.album
        }
        return LazyVStack(spacing: 18) {
            ForEach(groups.keys.sorted(), id: \.self) { album in
                VStack(alignment: .leading, spacing: 8) {
                    Text(album).font(.title3.bold()).padding(.horizontal, 4)
                    ForEach(groups[album] ?? []) { track in trackRow(track, queue: groups[album] ?? []) }
                }
            }
        }
        .padding(.horizontal)
    }

    private var favorites: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(spacing: 16) {
                        header("Favorites", subtitle: "The songs you love.")
                        let favs = sortedTracks.filter { p.isFavorite($0) }
                        if favs.isEmpty {
                            empty("heart", "No favorites yet", "Tap the heart beside a song to add it here.")
                        } else {
                            LazyVStack(spacing: compactRows ? 5 : 10) {
                                ForEach(favs) { track in
                                    trackRow(track, queue: favs)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }


    private var recent: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(spacing: 16) {
                        header("Recent", subtitle: "Recently added to your library.")
                        let recentTracks = Array(p.tracks.reversed())
                        if recentTracks.isEmpty {
                            empty("clock", "No recent music", "Imported songs will appear here.")
                        } else {
                            LazyVStack(spacing: compactRows ? 5 : 10) {
                                ForEach(recentTracks) { track in
                                    trackRow(track, queue: recentTracks)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var albumsTab: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(spacing: 16) {
                        header("Albums", subtitle: "Browse your music by album.")
                        if p.tracks.isEmpty {
                            empty("square.stack", "No albums yet", "Import music to build your album library.")
                        } else {
                            albumLibrary
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func header(_ title: String, subtitle: String, count: Int? = nil) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.largeTitle.bold())
                    if let count = count {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Button { musicInfoTarget = nil; showSearch = true } label: {
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
            Menu {
                Button { selectMode.toggle(); if !selectMode { selectedIDs.removeAll() } } label: {
                    Label(selectMode ? "Done Selecting" : "Select", systemImage: "checkmark.circle")
                }
                Button { musicInfoTarget = nil; showSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    ForEach(LibrarySort.allCases) { option in
                        Button { librarySort = option.rawValue } label: {
                            if librarySort == option.rawValue { Label(option.rawValue, systemImage: "checkmark") } else { Text(option.rawValue) }
                        }
                    }
                }
                Menu("Filter", systemImage: "line.3.horizontal.decrease") {
                    Button { libraryFilter = "All" } label: { Label("All songs", systemImage: libraryFilter == "All" ? "checkmark" : "music.note") }
                    Button { libraryFilter = "Favorites" } label: { Label("Favorites", systemImage: libraryFilter == "Favorites" ? "checkmark" : "heart") }
                }
                Button { gridMode.toggle() } label: { Label(gridMode ? "List" : "Grid", systemImage: gridMode ? "list.bullet" : "square.grid.2x2") }
                Button { tab = 4 } label: { Label("Settings", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
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
                Menu {
                    Button { musicInfoTarget = t; showSearch = true } label: {
                        Label("Search Music Info", systemImage: "magnifyingglass")
                    }
                    Button(role: .destructive) { p.remove(t) } label: {
                        Label("Remove from Library", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
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

            Menu {
                Button {
                    musicInfoTarget = t
                    showSearch = true
                } label: {
                    Label("Search Music Info Online", systemImage: "magnifyingglass.circle")
                }
                Button(role: .destructive) {
                    p.remove(t)
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").padding(8)
            }
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
            Button(role: .destructive) {
                p.remove(t)
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
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

            VStack(alignment: .leading) {
                Text(p.current?.title ?? "").bold().lineLimit(1)
                Text(p.current?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
