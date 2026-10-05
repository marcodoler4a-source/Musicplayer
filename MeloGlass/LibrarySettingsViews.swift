import SwiftUI
import UIKit

struct MusicInfoSearchView: View {
    @EnvironmentObject var p: PlayerModel
    @Environment(\.dismiss) private var dismiss
    let target: Track?
    @State private var query: String
    @State private var results: [OnlineMusicInfo] = []
    @State private var searching = false
    @State private var errorText: String?
    @State private var applyingID: String?

    init(target: Track? = nil) {
        self.target = target
        let initial = [target?.title, target?.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        _query = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        TextField("Song title and artist", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        Button { Task { await search() } } label: {
                            Image(systemName: "magnifyingglass").font(.title3)
                        }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
                    }.padding(.horizontal)

                    if searching { ProgressView("Searching MusicBrainz…").padding() }
                    if let errorText { Text(errorText).foregroundStyle(.secondary).multilineTextAlignment(.center).padding() }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(results) { item in
                                MusicInfoResultCard(
                                    item: item,
                                    canApply: target != nil,
                                    isApplying: applyingID == item.id
                                ) {
                                    if let target {
                                        Task { await apply(item, to: target) }
                                    }
                                }
                                .disabled(applyingID != nil)
                            }
                        }.padding(.horizontal)
                    }
                }
            }
            .navigationTitle(target == nil ? "Search Music Info" : "Find Music Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { if target != nil && !query.isEmpty { await search() } }
        }.preferredColorScheme(.dark)
    }

    @MainActor private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true; errorText = nil
        do {
            results = try await MusicInfoService.search(q)
            if results.isEmpty { errorText = "No matching music information found." }
        } catch {
            results = []; errorText = "Could not search music information. Check your internet connection and try again."
        }
        searching = false
    }

    @MainActor private func apply(_ item: OnlineMusicInfo, to track: Track) async {
        applyingID = item.id
        let art = await MusicInfoService.artwork(releaseID: item.releaseID)
        p.applyMusicInfo(to: track, info: item, artwork: art)
        applyingID = nil
        dismiss()
    }
}

struct MusicInfoResultCard: View {
    let item: OnlineMusicInfo
    let canApply: Bool
    let isApplying: Bool
    let apply: () -> Void
    @State private var artworkData: Data?
    @State private var artworkLoaded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let artworkData, let image = UIImage(data: artworkData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.08))
                        if artworkLoaded {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
            .frame(width: 82, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !item.album.isEmpty {
                    Label(item.album, systemImage: "square.stack")
                        .font(.caption)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if !item.releaseDate.isEmpty {
                        Text(item.releaseDate).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !item.genre.isEmpty {
                        Text(item.genre).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if canApply {
                    Button(action: apply) {
                        if isApplying {
                            ProgressView()
                        } else {
                            Label("Use Info + Cover", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .task(id: item.releaseID) {
            artworkData = await MusicInfoService.artwork(releaseID: item.releaseID)
            artworkLoaded = true
        }
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
