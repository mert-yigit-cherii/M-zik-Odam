import SwiftUI

struct UpNextView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(player.text("Sıradaki", "Up Next")).font(.title2.bold())
                Spacer()
                if !player.upNextTracks.isEmpty {
                    Button(player.text("Kuyruğu Temizle", "Clear Queue"), role: .destructive) { player.clearUpNext() }
                }
                Button(player.text("Bitti", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if player.upNextTracks.isEmpty {
                ContentUnavailableView(
                    player.text("Kuyruk boş", "Queue is empty"),
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    description: Text(player.text("Bir parçada ‘Sıradaki Çal’ veya ‘Daha Sonra Çal’ seçin.", "Choose ‘Play Next’ or ‘Play Later’ on a track."))
                )
            } else {
                List {
                    ForEach(player.upNextTracks) { track in
                        HStack(spacing: 10) {
                            CoverArt(data: track.coverData, size: 34, accent: player.accent.color)
                            VStack(alignment: .leading) {
                                Text(track.title).lineLimit(1)
                                Text(track.artist.isEmpty ? player.text("Bilinmeyen sanatçı", "Unknown artist") : track.artist).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { player.removeFromUpNext(track) } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.plain).accessibilityLabel(player.text("Kuyruktan çıkar", "Remove from queue"))
                        }
                    }
                    .onMove(perform: player.moveUpNext)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 440, minHeight: 330)
    }
}
