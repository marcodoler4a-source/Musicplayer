import SwiftUI

@main
struct MeloPlayerApp: App {
    @StateObject private var player = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}
