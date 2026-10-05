import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @EnvironmentObject var p: PlayerModel
    @State private var importing = false
    @State private var showPlayer = false
    @State private var showSearch = false
    @State private var tab = 0

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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                library
                    .tag(0)
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                favorites
                    .tag(1)
                    .tabItem { Label("Favorites", systemImage: "heart.fill") }

                AppearanceSettingsView()
                    .tag(2)
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
            .tint(accent)

            if p.current != nil && showMiniPlayer && tab != 2 {
                MiniPlayer()
                    .onTapGesture { showPlayer = true }
                    .padding(.bottom, 49)
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingView().environmentObject(p)
        }
        .sheet(isPresented: $showSearch) {
            MusicInfoSearchView().environmentObject(p)
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.audio],
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
                ScrollView {
                    VStack(spacing: 16) {
                        header("Library", subtitle: "Your music, beautifully local.")
                        if p.tracks.isEmpty {
                            empty(
                                "music.note.list",
                                "Import your music",
                                "Add MP3, M4A, AAC, WAV and other iOS-supported audio files."
                            )
                        } else {
                            LazyVStack(spacing: compactRows ? 5 : 10) {
                                ForEach(sortedTracks) { track in
                                    trackRow(track)
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
                                    trackRow(track)
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

    private func header(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSearch = true } label: {
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

    private func trackRow(_ t: Track) -> some View {
        HStack(spacing: 12) {
            Button {
                p.play(t)
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
