import SwiftUI
@main struct MeloGlassApp: App { @StateObject private var player = PlayerModel(); var body: some Scene { WindowGroup { ContentView().environmentObject(player).preferredColorScheme(.dark) } } }
