import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                CoverArt(data: player.currentTrack?.coverData, size: 56, accent: player.accent.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.currentTrack?.title ?? player.text("Bir parça seç", "Choose a track")).fontWeight(.semibold).lineLimit(1)
                    Text(player.currentTrack?.artist ?? player.text("Çalmaya hazır", "Ready to play")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            Slider(value: Binding(get: { player.currentTime }, set: player.seek), in: 0...max(player.duration, 1)).tint(player.accent.color)
            HStack(spacing: 18) {
                Button(action: player.previous) { Image(systemName: "backward.fill") }.accessibilityLabel(player.text("Önceki parça", "Previous track"))
                Button(action: player.togglePlayback) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 30, height: 30) }
                    .buttonStyle(.borderedProminent).tint(player.accent.color).clipShape(Circle())
                    .accessibilityLabel(player.isPlaying ? player.text("Duraklat", "Pause") : player.text("Çal", "Play"))
                Button(action: player.next) { Image(systemName: "forward.fill") }.accessibilityLabel(player.text("Sonraki parça", "Next track"))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 310)
        .background(AmbientNowPlayingBackground().environmentObject(player))
    }
}
