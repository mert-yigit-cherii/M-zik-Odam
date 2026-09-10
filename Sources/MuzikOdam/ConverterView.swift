import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ConverterView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var converter: ConverterStore
    @Environment(\.dismiss) private var dismiss
    @State private var format: ConversionFormat = .m4a
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.text("Dönüştürücü", "Converter")).font(.title.bold())
                    Text(player.text("Dönüştürme yalnızca bu Mac'te yapılır.", "Conversion happens only on this Mac.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(player.text("Bitti", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                Picker(player.text("Çıktı formatı", "Output format"), selection: $format) {
                    ForEach(ConversionFormat.allCases) { Text($0.title(player.language)).tag($0) }
                }.frame(width: 180)
                Button(player.text("Dosya Ekle…", "Add Files…"), action: chooseFiles)
                Spacer()
                Button(player.text("Çıktı Klasörü…", "Output Folder…"), action: converter.chooseOutputFolder)
                Text(converter.outputFolder.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(player.text("Bu sürüm Apple'ın yerel encoder'ı ile gerçek AAC/M4A çıktısı üretir. MP3, Opus, FLAC, WAV ve AIFF encoder'ları paketlenmemiştir.", "This build creates real AAC/M4A output with Apple's local encoder. MP3, Opus, FLAC, WAV, and AIFF encoders are not bundled.")).font(.caption).foregroundStyle(.secondary)
            Group {
                if converter.tasks.isEmpty {
                    ContentUnavailableView(player.text("Dönüştürme kuyruğu boş", "Conversion queue is empty"), systemImage: "arrow.triangle.2.circlepath", description: Text(player.text("Dosyaları buraya sürükleyin veya Dosya Ekle'yi kullanın.", "Drop files here or use Add Files.")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(converter.tasks) { task in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: task.state)).foregroundStyle(color(for: task.state))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.sourceURL.lastPathComponent).lineLimit(1)
                                Text(task.format.title(player.language) + " • " + task.state.title(player.language)).font(.caption).foregroundStyle(.secondary)
                                if let error = task.errorMessage { Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2) }
                            }
                            Spacer()
                            if task.state == .completed, let output = task.outputURL {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([output]) } label: { Image(systemName: "folder") }.buttonStyle(.plain).accessibilityLabel(player.text("Finder'da göster", "Show in Finder"))
                                Button { player.addFiles([output]) } label: { Image(systemName: "text.badge.plus") }.buttonStyle(.plain).accessibilityLabel(player.text("Kütüphaneye ekle", "Add to library"))
                            }
                            if task.state == .waiting || task.state == .converting {
                                Button { converter.cancel(task) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).accessibilityLabel(player.text("İptal", "Cancel"))
                            } else if task.state == .failed || task.state == .cancelled {
                                Button { converter.retry(task) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel(player.text("Yeniden dene", "Retry"))
                            }
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isTargeted ? player.accent.color : .clear, lineWidth: 2))
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: acceptDrop)
            HStack {
                Button(player.text("Geçmişi Temizle", "Clear History"), role: .destructive, action: converter.clearHistory).disabled(converter.isConverting || converter.tasks.isEmpty)
                Spacer()
                Button(converter.isConverting ? player.text("Dönüştürülüyor…", "Converting…") : player.text("Dönüştürmeyi Başlat", "Start Conversion"), action: converter.start).buttonStyle(.borderedProminent).disabled(converter.isConverting || !converter.tasks.contains(where: { $0.state == .waiting }))
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 510)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = player.text("Dönüştürülecek dosyaları seç", "Choose files to convert")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        converter.add(urls: panel.urls, format: format)
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { converter.add(urls: [url], format: format) }
            }
        }
        return true
    }
    private func icon(for state: ConversionState) -> String { switch state { case .waiting: "clock"; case .converting: "arrow.triangle.2.circlepath"; case .completed: "checkmark.circle.fill"; case .failed: "exclamationmark.triangle.fill"; case .cancelled: "xmark.circle.fill" } }
    private func color(for state: ConversionState) -> Color { switch state { case .completed: .green; case .failed: .red; case .cancelled: .secondary; case .converting: player.accent.color; case .waiting: .secondary } }
}
