import SwiftUI
import PhotosUI
import UIKit

struct MusixArtistSelection: Identifiable {
    let name: String
    var id: String { name }
}

@MainActor
final class MusixArtistCoverStore: ObservableObject {
    static let shared = MusixArtistCoverStore()
    @Published private var revision = 0
    private var cache: [String: Data] = [:]
    private let folder: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("ArtistCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func url(for artist: String) -> URL {
        // A stable filesystem-safe identifier; no external hashing dependency.
        let encoded = Data(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)
            .base64Encoded().replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return folder.appendingPathComponent(encoded + ".jpg")
    }

    func hasCover(for artist: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: artist).path)
    }

    func cover(for artist: String) -> Data? {
        _ = revision
        if let existing = cache[artist] { return existing }
        guard let data = try? Data(contentsOf: url(for: artist)) else { return nil }
        cache[artist] = data
        return data
    }

    func save(image: UIImage, for artist: String) {
        let maxSide: CGFloat = 700
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let target = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let data = resized.jpegData(compressionQuality: 0.83) else { return }
        do {
            try data.write(to: url(for: artist), options: .atomic)
            cache[artist] = data
            revision += 1
        } catch {
            print("Artist cover save failed: \(error)")
        }
    }

    func remove(artist: String) {
        try? FileManager.default.removeItem(at: url(for: artist))
        cache.removeValue(forKey: artist)
        revision += 1
    }
}

enum MusixArtistCoverSearch {
    static func open(_ artist: String) {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: "\(artist) artist portrait")]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

struct MusixArtistCoverEditor: View {
    let artist: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var covers = MusixArtistCoverStore.shared
    @State private var photo: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Group {
                    if let data = covers.cover(for: artist), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.square.fill").resizable().scaledToFit().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 170, height: 170).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(artist).font(.title2.bold())
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { MusixArtistCoverSearch.open(artist) } label: {
                    Label("Search Artist Photo Online", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text("Online search opens your browser. Save a picture to Photos, then return here and choose it.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if covers.hasCover(for: artist) {
                    Button(role: .destructive) { covers.remove(artist: artist) } label: {
                        Label("Reset to Song Artwork", systemImage: "arrow.counterclockwise")
                    }
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Artist Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onChange(of: photo) { newValue in
                guard let newValue else { return }
                Task {
                    guard let data = try? await newValue.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        errorMessage = "Could not load the selected image."
                        return
                    }
                    covers.save(image: image, for: artist)
                }
            }
            .alert("Image Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
