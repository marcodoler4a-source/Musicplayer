import SwiftUI

struct FloatingLyricsView: View {
    @EnvironmentObject var p: PlayerModel

    var body: some View {
        if p.floatingLyrics, p.current != nil {
            HStack(spacing: 12) {
                Image(systemName: "quote.bubble.fill")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    Text("FLOATING LYRICS")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.65))
                    Text(p.activeLyric?.text.isEmpty == false ? (p.activeLyric?.text ?? "") : "♪")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .animation(.easeInOut(duration: 0.2), value: p.activeLyric?.id)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
}
