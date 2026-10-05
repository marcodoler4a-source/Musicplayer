import SwiftUI

struct FloatingLyricsView: View {
    @EnvironmentObject var p: PlayerModel
    var body: some View {
        if p.floatingLyrics, p.current != nil {
            VStack(spacing:4) {
                HStack(spacing:8) {
                    Image(systemName:"quote.bubble.fill").font(.caption)
                    Text(p.current?.title ?? "").font(.caption.bold()).lineLimit(1)
                    Spacer()
                    Button { p.floatingLyrics=false } label:{ Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain)
                }.foregroundStyle(.white.opacity(.75))
                Text(p.activeLyric?.text ?? (p.current?.lyrics.isEmpty == false ? "♪" : "No synced lyrics loaded"))
                    .font(.headline.weight(.semibold)).multilineTextAlignment(.center).frame(maxWidth:.infinity)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal,16).padding(.vertical,12)
            .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(.14)))
            .padding(.horizontal,18).padding(.bottom,86)
            .transition(.move(edge:.bottom).combined(with:.opacity))
        }
    }
}
