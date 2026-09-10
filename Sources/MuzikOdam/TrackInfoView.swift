import SwiftUI
import AppKit

struct TrackInfoView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dismiss) private var dismiss
    let track: Track

    private var fileSize: String {
        let bytes = (try? track.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func date(_ value: Date?) -> String {
        guard let value else { return player.text("Bilinmiyor", "Unknown") }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        let stats = player.statistics(for: track)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                CoverArt(data: track.coverData, size: 88, accent: player.accent.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.title2.bold()).lineLimit(2)
                    Text(track.artist.isEmpty ? player.text("Bilinmeyen sanatçı", "Unknown artist") : track.artist).foregroundStyle(.secondary)
                    Text(track.album.isEmpty ? player.text("Bilinmeyen albüm", "Unknown album") : track.album).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(player.text("Bitti", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Form {
                Section(player.text("Dosya", "File")) {
                    LabeledContent(player.text("Dosya adı", "File name"), value: track.url.lastPathComponent)
                    LabeledContent(player.text("Konum", "Location"), value: track.url.deletingLastPathComponent().path)
                    LabeledContent(player.text("Boyut", "Size"), value: fileSize)
                    LabeledContent(player.text("Format", "Format"), value: track.format)
                    LabeledContent(player.text("Süre", "Duration"), value: time(track.duration))
                }
                Section(player.text("Etiketler", "Tags")) {
                    LabeledContent(player.text("Tür", "Genre"), value: track.genre.isEmpty ? player.text("Bilinmiyor", "Unknown") : track.genre)
                    LabeledContent(player.text("Yıl", "Year"), value: track.year ?? player.text("Bilinmiyor", "Unknown"))
                }
                Section(player.text("Yerel istatistikler", "Local statistics")) {
                    LabeledContent(player.text("Çalma sayısı", "Play count"), value: String(stats.playCount))
                    LabeledContent(player.text("Atlama sayısı", "Skip count"), value: String(stats.skipCount))
                    LabeledContent(player.text("Eklenme tarihi", "Date added"), value: date(stats.dateAdded))
                    LabeledContent(player.text("Son çalınma", "Last played"), value: date(stats.lastPlayedDate))
                }
            }
            HStack {
                Button(player.text("Finder'da Göster", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([track.url]) }
                Spacer()
                Button(player.text("Çal", "Play")) { player.play(track) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 570, minHeight: 500)
    }

    private func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
