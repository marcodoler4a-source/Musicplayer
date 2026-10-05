import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @EnvironmentObject var p: PlayerModel
    @State private var importing = false
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.black, Color(red: 0.03, green: 0.08, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("MeloGlass").font(.largeTitle.bold())
                                Text("Your music, beautifully local.").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { importing = true } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .padding(12)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                        .padding(.horizontal)

                        if p.tracks.isEmpty {
                            ContentUnavailableView(
                                "Import your music",
                                systemImage: "music.note.list",
                                description: Text("MP3, M4A, AAC, WAV and other iOS-supported audio files.")
                            )
                            .padding(.top, 70)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(p.tracks) { t in
                                    Button {
                                        p.play(t)
                                        showPlayer = true
                                    } label: {
                                        TrackRow(t: t)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }

                if p.current != nil {
                    VStack {
                        Spacer()
                        ZStack(alignment: .bottom) {
                            FloatingLyricsView()
                            MiniPlayer().onTapGesture { showPlayer = true }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPlayer) { NowPlayingView() }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    p.add(urls: urls)
                }
            }
        }
    }
}

struct TrackRow: View {
    let t: Track
    var body: some View {
        HStack(spacing: 12) {
            Artwork(data: t.artworkData).frame(width: 58, height: 58)
            VStack(alignment: .leading) {
                Text(t.title).font(.headline).lineLimit(1)
                Text(t.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "play.fill").foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct Artwork: View {
    let data: Data?
    var body: some View {
        Group {
            if let d = data, let i = UIImage(data: d) {
                Image(uiImage: i).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.blue.opacity(0.8), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            Artwork(data: p.current?.artworkData).frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text(p.current?.title ?? "").bold().lineLimit(1)
                Text(p.current?.artist ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { p.toggle() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            Button { p.next() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding()
    }
}
