import SwiftUI

/// A live, persistent glass treatment for existing Musix surfaces.
/// iOS material blur radius is system controlled; the tint and material blend
/// provide an immediately visible intensity adjustment without private APIs.
struct MusixGlassBackground<S: InsettableShape>: View {
    let shape: S
    @AppStorage("glassIntensity") private var intensity = 0.75
    @Environment(\.colorScheme) private var colorScheme

    private var level: Double { min(1, max(0.2, intensity)) }

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(colorScheme == .dark ? Color(red: 0.025, green: 0.09, blue: 0.20) : Color.white)
                    .opacity((1 - level) * (colorScheme == .dark ? 0.88 : 0.92))
            }
            .overlay {
                shape.fill(Color.cyan.opacity(level * (colorScheme == .dark ? 0.14 : 0.10)))
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 + level * 0.22 : 0.14 + level * 0.28), lineWidth: 0.8)
            }
            .animation(.easeInOut(duration: 0.16), value: level)
    }
}
