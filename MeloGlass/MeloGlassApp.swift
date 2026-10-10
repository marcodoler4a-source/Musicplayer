import SwiftUI

@main struct MeloGlassApp: App {
    @StateObject private var player = PlayerModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .inactive || phase == .background {
                        player.persistSessionForBackground()
                    }
                }
        }
    }
}
