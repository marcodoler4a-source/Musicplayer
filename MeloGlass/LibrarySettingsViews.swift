import SwiftUI

struct MusicInfoSearchView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var scope = 0
    private var results: [Track] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return p.tracks }
        return p.tracks.filter { t in
            switch scope {
            case 1: return t.artist.lowercased().contains(q)
            case 2: return t.album.lowercased().contains(q)
            default: return t.title.lowercased().contains(q) || t.artist.lowercased().contains(q) || t.album.lowercased().contains(q)
            }
        }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Picker("Search", selection: $scope) {
                        Text("All").tag(0); Text("Artist").tag(1); Text("Album").tag(2)
                    }.pickerStyle(.segmented).padding(.horizontal)
                    if results.isEmpty {
                        Spacer(); Image(systemName:"magnifyingglass").font(.system(size:42)).foregroundStyle(.secondary)
                        Text("No music info found").font(.title3.bold()); Spacer()
                    } else {
                        ScrollView { LazyVStack(spacing: 8) {
                            ForEach(results) { t in
                                Button { p.play(t); dismiss() } label: {
                                    HStack(spacing:12) {
                                        Artwork(data:t.artworkData).frame(width:54,height:54)
                                        VStack(alignment:.leading,spacing:3) {
                                            Text(t.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                            Text(t.artist).foregroundStyle(.secondary).lineLimit(1)
                                            if !t.album.isEmpty { Text(t.album).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                        }
                                        Spacer()
                                        if p.isFavorite(t) { Image(systemName:"heart.fill").foregroundStyle(.blue) }
                                    }.padding(10).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal) }
                    }
                }
            }
            .navigationTitle("Search Music Info").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$query,prompt:"Title, artist or album")
            .toolbar { ToolbarItem(placement:.topBarTrailing){ Button("Done"){dismiss()} } }
        }.preferredColorScheme(.dark)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("accentChoice") private var accentChoice = "Blue"
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("showArtwork") private var showArtwork = true
    @AppStorage("showMiniPlayer") private var showMiniPlayer = true
    @AppStorage("largePlayerButtons") private var largePlayerButtons = true
    @AppStorage("glassIntensity") private var glassIntensity = 0.75
    @AppStorage("librarySort") private var librarySort = LibrarySort.title.rawValue
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Accent",selection:$accentChoice){ Text("Blue").tag("Blue"); Text("Purple").tag("Purple"); Text("Green").tag("Green"); Text("Pink").tag("Pink") }
                    Toggle("Show album artwork",isOn:$showArtwork)
                    Toggle("Compact library rows",isOn:$compactRows)
                    HStack { Text("Glass intensity"); Slider(value:$glassIntensity,in:0.2...1) }
                }
                Section("Player Buttons") {
                    Toggle("Large playback buttons",isOn:$largePlayerButtons)
                    Toggle("Show mini player",isOn:$showMiniPlayer)
                }
                Section("Library") {
                    Picker("Sort music",selection:$librarySort){ ForEach(LibrarySort.allCases){ Text($0.rawValue).tag($0.rawValue) } }
                }
                Section("Lyrics") {
                    Text("Floating lyrics, synced lyrics search and LRC files remain available from Now Playing.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Customize")
        }
    }
}
